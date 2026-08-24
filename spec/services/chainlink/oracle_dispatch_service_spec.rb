# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Chainlink::OracleDispatchService do
  let(:cluster) { create(:cluster) }
  let(:tree) { create(:tree, cluster: cluster, peaq_did: "did:peaq:0x#{"a" * 40}") }
  let(:telemetry_log) { create(:telemetry_log, tree: tree, verified_by_iotex: true, zk_proof_ref: "zk-proof-abc123") }

  before do
    silence_broadcasts!(:tree_map)
  end

  describe "#dispatch!" do
    it "updates the telemetry log with chainlink_request_id and dispatched status" do
      service = described_class.new(telemetry_log)
      request_id = service.dispatch!

      telemetry_log.reload
      expect(telemetry_log.chainlink_request_id).to eq(request_id)
      expect(telemetry_log.oracle_status).to eq("dispatched")
    end

    it "returns a local correlation-marker request id" do
      service = described_class.new(telemetry_log)
      request_id = service.dispatch!

      expect(request_id).to be_a(String)
      expect(request_id).to start_with("chainlink-req-")
    end

    it "generates a unique marker per dispatch" do
      other_log = create(:telemetry_log, tree: tree, verified_by_iotex: true)

      first = described_class.new(telemetry_log).dispatch!
      second = described_class.new(other_log).dispatch!

      expect(first).not_to eq(second)
    end

    it "raises DispatchError when telemetry_log is not verified by IoTeX" do
      unverified_log = create(:telemetry_log, tree: tree, verified_by_iotex: false)
      service = described_class.new(unverified_log)

      expect { service.dispatch! }.to raise_error(
        Chainlink::OracleDispatchService::DispatchError,
        /не верифіковано IoTeX/
      )
      expect(unverified_log.reload.chainlink_request_id).to be_nil
    end

    # [ARCH.53]: демоут-інваріант — dispatch суто локальний (жодного RPC/LINK-cost).
    it "never opens an RPC connection" do
      allow(Web3::RpcConnectionPool).to receive(:client_for)

      described_class.new(telemetry_log).dispatch!

      expect(Web3::RpcConnectionPool).not_to have_received(:client_for)
    end
  end
end
