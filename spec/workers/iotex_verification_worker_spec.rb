# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe IotexVerificationWorker, type: :worker do
  let(:cluster) { create(:cluster) }
  let(:tree) { create(:tree, cluster: cluster, peaq_did: "did:peaq:0x#{"a" * 40}") }
  let(:telemetry_log) { create(:telemetry_log, tree: tree) }

  before do
    silence_broadcasts!(:tree_map)
  end

  describe "#perform" do
    it "calls Iotex::W3bstreamVerificationService and updates telemetry_log" do
      zk_proof_ref = "zk-proof-abc123"
      service = instance_double(Iotex::W3bstreamVerificationService)
      allow(Iotex::W3bstreamVerificationService).to receive(:new).with(telemetry_log).and_return(service)
      allow(service).to receive(:verify!).and_return(zk_proof_ref)

      described_class.new.perform(telemetry_log.id_value, telemetry_log.created_at.iso8601(6))

      telemetry_log.reload
      expect(telemetry_log.verified_by_iotex).to be true
      expect(telemetry_log.zk_proof_ref).to eq(zk_proof_ref)
    end

    it "enqueues ChainlinkDispatchWorker after successful verification" do
      zk_proof_ref = "zk-proof-abc123"
      service = instance_double(Iotex::W3bstreamVerificationService)
      allow(Iotex::W3bstreamVerificationService).to receive(:new).with(telemetry_log).and_return(service)
      allow(service).to receive(:verify!).and_return(zk_proof_ref)

      described_class.new.perform(telemetry_log.id_value, telemetry_log.created_at.iso8601(6))

      expect(ChainlinkDispatchWorker.jobs.size).to eq(1)
      expect(ChainlinkDispatchWorker.jobs.first["args"]).to eq([
        telemetry_log.id_value, telemetry_log.created_at.iso8601(6)
      ])
    end

    it "skips re-processing when telemetry_log is already verified and dispatched" do
      telemetry_log.update_columns(verified_by_iotex: true, zk_proof_ref: "existing-proof",
                                   chainlink_request_id: "existing-req", oracle_status: "dispatched")

      allow(Iotex::W3bstreamVerificationService).to receive(:new)

      described_class.new.perform(telemetry_log.id_value, telemetry_log.created_at.iso8601(6))

      expect(Iotex::W3bstreamVerificationService).not_to have_received(:new)

      telemetry_log.reload
      expect(telemetry_log.zk_proof_ref).to eq("existing-proof")
      expect(ChainlinkDispatchWorker.jobs).to be_empty
    end

    # [ARCH.53/B1] Recover the verify→dispatch enqueue-after-commit gap: a log left
    # verified_by_iotex=true with chainlink_request_id nil + oracle pending (crash between
    # update! and perform_async) is re-enqueued instead of stranded.
    it "re-enqueues ChainlinkDispatchWorker when verified but dispatch was stranded (crash recovery)" do
      telemetry_log.update_columns(verified_by_iotex: true, zk_proof_ref: "existing-proof",
                                   chainlink_request_id: nil, oracle_status: "pending")

      allow(Iotex::W3bstreamVerificationService).to receive(:new)

      described_class.new.perform(telemetry_log.id_value, telemetry_log.created_at.iso8601(6))

      expect(Iotex::W3bstreamVerificationService).not_to have_received(:new)

      expect(ChainlinkDispatchWorker.jobs.size).to eq(1)
      expect(ChainlinkDispatchWorker.jobs.first["args"]).to eq([
        telemetry_log.id_value, telemetry_log.created_at.iso8601(6)
      ])
    end

    it "returns early when telemetry_log is not found" do
      allow(Rails.logger).to receive(:error).with(/не знайдено/)
      allow(Iotex::W3bstreamVerificationService).to receive(:new)

      described_class.new.perform(-1, Time.current.iso8601(6))

      expect(Rails.logger).to have_received(:error).with(/не знайдено/)
      expect(Iotex::W3bstreamVerificationService).not_to have_received(:new)
    end

    # [PERF.1/S6.16] Битий created_at_iso — зіпсована ПІДКАЗКА прунінгу, а не
    # підстава втратити мінт. Доти рукописний `find_log` ловив ArgumentError і
    # віддавав nil, тож воркер завершувався «успішно», не зробивши НІЧОГО: лог
    # існує, робота легітимна, а помилка в параметрі оптимізації з'їдала першу
    # ланку мінт-ланцюга — мовчки, без ретраю й без DeadSet. One-Home
    # `partition_pruned` відкочується в lookup без прунінгу (з обліком
    # деградації лічильником) і роботу доводить до кінця.
    it "falls back to an unpruned lookup and still verifies when created_at_iso is malformed" do
      allow(Rails.logger).to receive(:warn)
      service = instance_double(Iotex::W3bstreamVerificationService)
      allow(Iotex::W3bstreamVerificationService).to receive(:new).with(telemetry_log).and_return(service)
      allow(service).to receive(:verify!).and_return("zk-proof-degraded")

      described_class.new.perform(telemetry_log.id_value, "not-a-valid-iso-date")

      expect(telemetry_log.reload.verified_by_iotex).to be true
      expect(Rails.logger).to have_received(:warn).with(/битий created_at_iso/)
    end

    it "re-raises VerificationError for Sidekiq retry" do
      service = instance_double(Iotex::W3bstreamVerificationService)
      allow(Iotex::W3bstreamVerificationService).to receive(:new).with(telemetry_log).and_return(service)
      allow(service).to receive(:verify!).and_raise(
        Iotex::W3bstreamVerificationService::VerificationError, "W3bstream timeout"
      )

      expect {
        described_class.new.perform(telemetry_log.id_value, telemetry_log.created_at.iso8601(6))
      }.to raise_error(Iotex::W3bstreamVerificationService::VerificationError, /W3bstream timeout/)

      telemetry_log.reload
      expect(telemetry_log.verified_by_iotex).to be false
    end

    it "re-raises CircuitOpenError so Sidekiq retries later" do
      allow_any_instance_of(described_class).to receive(:with_circuit_breaker)
        .and_raise(Web3CircuitBreaker::CircuitOpenError, "Circuit OPEN")
      expect {
        described_class.new.perform(telemetry_log.id_value, telemetry_log.created_at.iso8601(6))
      }.to raise_error(Web3CircuitBreaker::CircuitOpenError)
    end

    it "uses web3_critical queue" do
      expect(described_class.get_sidekiq_options["queue"]).to eq("web3_critical")
    end

    it "has retry set to 5" do
      expect(described_class.get_sidekiq_options["retry"]).to eq(5)
    end
  end

  # -----------------------------------------------------------------------
  # S3.1: Guard clause — IoTeX verification (ZK-proof rejection)
  # -----------------------------------------------------------------------
  describe "guard clauses (S3.1)" do
    it "rejects already-verified logs without calling W3bstream" do
      telemetry_log.update_columns(verified_by_iotex: true, zk_proof_ref: "existing-proof",
                                   chainlink_request_id: "existing-req", oracle_status: "dispatched")

      allow(Iotex::W3bstreamVerificationService).to receive(:new)

      described_class.new.perform(telemetry_log.id_value, telemetry_log.created_at.iso8601(6))

      expect(Iotex::W3bstreamVerificationService).not_to have_received(:new)
    end

    it "does not chain ChainlinkDispatchWorker when verification fails" do
      service = instance_double(Iotex::W3bstreamVerificationService)
      allow(Iotex::W3bstreamVerificationService).to receive(:new).with(telemetry_log).and_return(service)
      allow(service).to receive(:verify!).and_raise(
        Iotex::W3bstreamVerificationService::VerificationError, "Invalid ZK proof data"
      )

      expect {
        described_class.new.perform(telemetry_log.id_value, telemetry_log.created_at.iso8601(6))
      }.to raise_error(Iotex::W3bstreamVerificationService::VerificationError)

      expect(ChainlinkDispatchWorker.jobs).to be_empty
    end

    it "does not set verified_by_iotex when verification fails" do
      service = instance_double(Iotex::W3bstreamVerificationService)
      allow(Iotex::W3bstreamVerificationService).to receive(:new).with(telemetry_log).and_return(service)
      allow(service).to receive(:verify!).and_raise(
        Iotex::W3bstreamVerificationService::VerificationError, "Fake telemetry detected"
      )

      expect {
        described_class.new.perform(telemetry_log.id_value, telemetry_log.created_at.iso8601(6))
      }.to raise_error(Iotex::W3bstreamVerificationService::VerificationError)

      telemetry_log.reload
      expect(telemetry_log.verified_by_iotex).to be false
      expect(telemetry_log.zk_proof_ref).to be_nil
    end

    it "preserves pipeline ordering: IoTeX verification before Chainlink dispatch" do
      zk_proof_ref = "zk-proof-order-test"
      service = instance_double(Iotex::W3bstreamVerificationService)
      allow(Iotex::W3bstreamVerificationService).to receive(:new).with(telemetry_log).and_return(service)
      allow(service).to receive(:verify!).and_return(zk_proof_ref)

      described_class.new.perform(telemetry_log.id_value, telemetry_log.created_at.iso8601(6))

      # Verify IoTeX flag set before Chainlink dispatched
      telemetry_log.reload
      expect(telemetry_log.verified_by_iotex).to be true
      expect(telemetry_log.zk_proof_ref).to eq(zk_proof_ref)
      expect(ChainlinkDispatchWorker.jobs.size).to eq(1)
    end
  end

  # [INF.22] Слід мусить нести ОБИДВА аргументи re-enqueue: `TelemetryLog`
  # партиційований, тож без `created_at` рядок не резолвиться, і оголошений спосіб
  # відновлення (ручний re-enqueue) стає недосяжним саме в момент, коли потрібен.
  # Пін цілиться в ЗМІСТ рядка, не в сам факт логування — інакше він зелений і на
  # сліді «щось не вдалося», з якого відновити не можна нічого.
  describe ".sidekiq_retries_exhausted" do
    it "logs both re-enqueue coordinates of the stranded log" do
      job = { "args" => [ 4242, "2026-03-06T01:02:03.000000Z" ] }
      allow(Rails.logger).to receive(:warn)

      described_class.sidekiq_retries_exhausted_block.call(job, StandardError.new("iotex down"))

      expect(Rails.logger).to have_received(:warn).with(/4242/)
      expect(Rails.logger).to have_received(:warn).with(/2026-03-06T01:02:03/)
    end

    it "does not raise — a terminal hook that throws destroys the trail it exists for" do
      job = { "args" => [ 1, nil ] }

      expect { described_class.sidekiq_retries_exhausted_block.call(job, StandardError.new("boom")) }
        .not_to raise_error
    end
  end
end
