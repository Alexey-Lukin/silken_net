# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChainlinkDispatchWorker, type: :worker do
  let(:cluster) { create(:cluster) }
  let(:tree) { create(:tree, cluster: cluster, peaq_did: "did:peaq:0x#{"a" * 40}") }
  let(:telemetry_log) { create(:telemetry_log, tree: tree, verified_by_iotex: true, zk_proof_ref: "zk-proof-abc123") }

  before do
    silence_broadcasts!(:tree_map)
  end

  describe "#perform" do
    it "calls Chainlink::OracleDispatchService and dispatches the log" do
      service = instance_double(Chainlink::OracleDispatchService)
      allow(Chainlink::OracleDispatchService).to receive(:new).with(telemetry_log).and_return(service)
      allow(service).to receive(:dispatch!).and_return("chainlink-req-abc123")

      described_class.new.perform(telemetry_log.id_value, telemetry_log.created_at.iso8601(6))

      expect(service).to have_received(:dispatch!)
    end

    it "skips dispatch when telemetry_log already has chainlink_request_id" do
      telemetry_log.update_columns(chainlink_request_id: "existing-req-id")

      allow(Chainlink::OracleDispatchService).to receive(:new)

      described_class.new.perform(telemetry_log.id_value, telemetry_log.created_at.iso8601(6))

      expect(Chainlink::OracleDispatchService).not_to have_received(:new)
    end

    it "returns early when telemetry_log is not found" do
      allow(Rails.logger).to receive(:error).with(/не знайдено/)
      allow(Chainlink::OracleDispatchService).to receive(:new)

      described_class.new.perform(-1, Time.current.iso8601(6))

      expect(Rails.logger).to have_received(:error).with(/не знайдено/)
      expect(Chainlink::OracleDispatchService).not_to have_received(:new)
    end

    it "re-raises DispatchError for Sidekiq retry" do
      service = instance_double(Chainlink::OracleDispatchService)
      allow(Chainlink::OracleDispatchService).to receive(:new).with(telemetry_log).and_return(service)
      allow(service).to receive(:dispatch!).and_raise(
        Chainlink::OracleDispatchService::DispatchError, "IoTeX not verified"
      )

      expect {
        described_class.new.perform(telemetry_log.id_value, telemetry_log.created_at.iso8601(6))
      }.to raise_error(Chainlink::OracleDispatchService::DispatchError, /IoTeX not verified/)
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

    context "when created_at_iso has invalid format" do
      # [PERF.1/S6.16] Дзеркало прикладу в IotexVerificationWorker: зіпсована
      # підказка прунінгу не сміє коштувати диспетчеризації до оракула. Доти
      # рукописний `find_log` віддавав nil, і воркер «успішно» не робив нічого.
      it "falls back to an unpruned lookup and still dispatches" do
        allow(Rails.logger).to receive(:warn)
        service = instance_double(Chainlink::OracleDispatchService)
        allow(Chainlink::OracleDispatchService).to receive(:new).with(telemetry_log).and_return(service)
        allow(service).to receive(:dispatch!).and_return("chainlink-req-degraded")

        described_class.new.perform(telemetry_log.id_value, "not-a-valid-iso-date")

        expect(service).to have_received(:dispatch!)
        expect(Rails.logger).to have_received(:warn).with(/битий created_at_iso/)
      end
    end
  end

  # -----------------------------------------------------------------------
  # S2.4: Prometheus metric ORACLE_DISPATCH_DURATION
  # -----------------------------------------------------------------------
  describe "Prometheus metrics (S2.4)" do
    it "observes ORACLE_DISPATCH_DURATION histogram on successful dispatch" do
      service = instance_double(Chainlink::OracleDispatchService)
      allow(Chainlink::OracleDispatchService).to receive(:new).with(telemetry_log).and_return(service)
      allow(service).to receive(:dispatch!).and_return("chainlink-req-abc123")

      metric = SilkenNet::Metrics::ORACLE_DISPATCH_DURATION
      allow(metric).to receive(:observe).with(a_value > 0)

      described_class.new.perform(telemetry_log.id_value, telemetry_log.created_at.iso8601(6))

      expect(metric).to have_received(:observe).with(a_value > 0)
    end

    # 🔴 [INF.26] Гістограма мусить бачити ПРОВАЛИ — інакше вона міряє «латентність
    # диспатчів, що вдались», називаючись «dispatch latency». Ціна survivorship bias
    # тут максимальна: деградований оракул, що таймаутить, не додає до p99 НІЧОГО,
    # тобто панель показує здорову латентність саме під час аварії.
    it "observes the latency of a FAILED dispatch too" do
      service = instance_double(Chainlink::OracleDispatchService)
      allow(Chainlink::OracleDispatchService).to receive(:new).with(telemetry_log).and_return(service)
      allow(service).to receive(:dispatch!)
        .and_raise(Chainlink::OracleDispatchService::DispatchError, "oracle timeout")

      metric = SilkenNet::Metrics::ORACLE_DISPATCH_DURATION
      allow(metric).to receive(:observe)

      expect {
        described_class.new.perform(telemetry_log.id_value, telemetry_log.created_at.iso8601(6))
      }.to raise_error(Chainlink::OracleDispatchService::DispatchError)

      expect(metric).to have_received(:observe).with(a_value > 0)
    end

    # ⊥ Дзеркальна межа, і без неї попередній пін штовхав би до «спостерігати завжди»:
    # circuit-open відмовляє за мікросекунди й НЕ є латентністю оракула — ті семпли
    # занизили б p99, тобто наш власний запобіжник малював би оракул швидшим, ніж він є.
    it "does NOT observe when our own breaker refuses (that is not oracle latency)" do
      allow_any_instance_of(described_class).to receive(:with_circuit_breaker)
        .and_raise(Web3CircuitBreaker::CircuitOpenError, "Circuit OPEN")

      metric = SilkenNet::Metrics::ORACLE_DISPATCH_DURATION
      allow(metric).to receive(:observe)

      expect {
        described_class.new.perform(telemetry_log.id_value, telemetry_log.created_at.iso8601(6))
      }.to raise_error(Web3CircuitBreaker::CircuitOpenError)

      expect(metric).not_to have_received(:observe)
    end

    it "does not observe ORACLE_DISPATCH_DURATION when log already dispatched" do
      telemetry_log.update_columns(chainlink_request_id: "existing-req-id")

      metric = SilkenNet::Metrics::ORACLE_DISPATCH_DURATION
      allow(metric).to receive(:observe)

      described_class.new.perform(telemetry_log.id_value, telemetry_log.created_at.iso8601(6))

      expect(metric).not_to have_received(:observe)
    end

    it "does not observe ORACLE_DISPATCH_DURATION when log not found" do
      metric = SilkenNet::Metrics::ORACLE_DISPATCH_DURATION
      allow(metric).to receive(:observe)

      allow(Rails.logger).to receive(:error)

      expect(metric).not_to have_received(:observe)
      described_class.new.perform(-1, Time.current.iso8601(6))
    end
  end

  # -----------------------------------------------------------------------
  # S3.1: Guard clause — Chainlink dispatch
  # -----------------------------------------------------------------------
  describe "guard clauses (S3.1)" do
    it "skips dispatch when log already has chainlink_request_id (idempotency)" do
      telemetry_log.update_columns(chainlink_request_id: "existing-req-id")

      allow(Chainlink::OracleDispatchService).to receive(:new)

      described_class.new.perform(telemetry_log.id_value, telemetry_log.created_at.iso8601(6))

      expect(Chainlink::OracleDispatchService).not_to have_received(:new)
    end

    it "preserves oracle_status as dispatched after successful dispatch" do
      service = instance_double(Chainlink::OracleDispatchService)
      allow(Chainlink::OracleDispatchService).to receive(:new).with(telemetry_log).and_return(service)
      allow(service).to receive(:dispatch!) do
        telemetry_log.update!(chainlink_request_id: "chainlink-req-guard-test", oracle_status: "dispatched")
        "chainlink-req-guard-test"
      end

      described_class.new.perform(telemetry_log.id_value, telemetry_log.created_at.iso8601(6))

      telemetry_log.reload
      expect(telemetry_log.oracle_status).to eq("dispatched")
      expect(telemetry_log.chainlink_request_id).to eq("chainlink-req-guard-test")
    end
  end
end
