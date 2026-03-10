# frozen_string_literal: true

require "rails_helper"

RSpec.describe Chainlink::OracleDispatchService do
  let(:cluster) { create(:cluster) }
  let(:tree) { create(:tree, cluster: cluster, peaq_did: "did:peaq:0x#{"a" * 40}") }
  let(:telemetry_log) { create(:telemetry_log, tree: tree, verified_by_iotex: true, zk_proof_ref: "zk-proof-abc123") }

  before do
    allow_any_instance_of(Tree).to receive(:broadcast_map_update)
  end

  describe "#dispatch!" do
    it "updates the telemetry log with chainlink_request_id and dispatched status" do
      service = described_class.new(telemetry_log)
      request_id = service.dispatch!

      telemetry_log.reload
      expect(telemetry_log.chainlink_request_id).to eq(request_id)
      expect(telemetry_log.oracle_status).to eq("dispatched")
    end

    it "returns a chainlink request id string" do
      service = described_class.new(telemetry_log)
      request_id = service.dispatch!

      expect(request_id).to be_a(String)
      expect(request_id).to start_with("chainlink-req-")
    end

    it "raises DispatchError when telemetry_log is not verified by IoTeX" do
      unverified_log = create(:telemetry_log, tree: tree, verified_by_iotex: false)
      service = described_class.new(unverified_log)

      expect { service.dispatch! }.to raise_error(
        Chainlink::OracleDispatchService::DispatchError,
        /не верифіковано IoTeX/
      )
    end

    it "builds payload with tree peaq_did, Lorenz state, and zk_proof_ref" do
      service = described_class.new(telemetry_log)

      # Access private method to verify payload structure
      payload = service.send(:build_chainlink_payload)

      expect(payload[:peaq_did]).to eq("did:peaq:0x#{"a" * 40}")
      expect(payload[:zk_proof_ref]).to eq("zk-proof-abc123")
      expect(payload[:lorenz_state][:sigma]).to eq(10)
      expect(payload[:lorenz_state][:rho]).to eq(28)
      expect(payload[:lorenz_state][:z_value]).to eq(telemetry_log.z_value.to_f)
      expect(payload[:tree_did]).to eq(tree.did)
      expect(payload[:telemetry_log_id]).to eq(telemetry_log.id)
    end
  end
end
