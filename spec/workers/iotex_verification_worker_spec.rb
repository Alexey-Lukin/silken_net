# frozen_string_literal: true

require "rails_helper"

RSpec.describe IotexVerificationWorker, type: :worker do
  let(:cluster) { create(:cluster) }
  let(:tree) { create(:tree, cluster: cluster, peaq_did: "did:peaq:0x#{"a" * 40}") }
  let(:telemetry_log) { create(:telemetry_log, tree: tree) }

  before do
    allow_any_instance_of(Tree).to receive(:broadcast_map_update)
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

    it "skips verification when telemetry_log is already verified" do
      telemetry_log.update_columns(verified_by_iotex: true, zk_proof_ref: "existing-proof")

      expect(Iotex::W3bstreamVerificationService).not_to receive(:new)

      described_class.new.perform(telemetry_log.id_value, telemetry_log.created_at.iso8601(6))

      telemetry_log.reload
      expect(telemetry_log.zk_proof_ref).to eq("existing-proof")
    end

    it "returns early when telemetry_log is not found" do
      expect(Rails.logger).to receive(:error).with(/не знайдено/)
      expect(Iotex::W3bstreamVerificationService).not_to receive(:new)

      described_class.new.perform(-1, Time.current.iso8601(6))
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

    it "uses web3 queue" do
      expect(described_class.get_sidekiq_options["queue"]).to eq("web3")
    end

    it "has retry set to 5" do
      expect(described_class.get_sidekiq_options["retry"]).to eq(5)
    end
  end
end
