# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChainlinkDispatchWorker, type: :worker do
  let(:cluster) { create(:cluster) }
  let(:tree) { create(:tree, cluster: cluster, peaq_did: "did:peaq:0x#{"a" * 40}") }
  let(:telemetry_log) { create(:telemetry_log, tree: tree, verified_by_iotex: true, zk_proof_ref: "zk-proof-abc123") }

  before do
    allow_any_instance_of(Tree).to receive(:broadcast_map_update)
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

      expect(Chainlink::OracleDispatchService).not_to receive(:new)

      described_class.new.perform(telemetry_log.id_value, telemetry_log.created_at.iso8601(6))
    end

    it "returns early when telemetry_log is not found" do
      expect(Rails.logger).to receive(:error).with(/не знайдено/)
      expect(Chainlink::OracleDispatchService).not_to receive(:new)

      described_class.new.perform(-1, Time.current.iso8601(6))
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

    it "uses web3 queue" do
      expect(described_class.get_sidekiq_options["queue"]).to eq("web3")
    end

    it "has retry set to 5" do
      expect(described_class.get_sidekiq_options["retry"]).to eq(5)
    end
  end
end
