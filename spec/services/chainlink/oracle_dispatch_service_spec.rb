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

    it "returns a chainlink request id string in stub mode" do
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

    it "builds payload with Lorenz constants from SilkenNet::Attractor" do
      service = described_class.new(telemetry_log)

      payload = service.send(:build_chainlink_payload)

      expect(payload[:peaq_did]).to eq("did:peaq:0x#{"a" * 40}")
      expect(payload[:zk_proof_ref]).to eq("zk-proof-abc123")
      expect(payload[:lorenz_state][:sigma]).to eq(SilkenNet::Attractor::BASE_SIGMA.to_f)
      expect(payload[:lorenz_state][:rho]).to eq(SilkenNet::Attractor::BASE_RHO.to_f)
      expect(payload[:lorenz_state][:beta]).to eq(SilkenNet::Attractor::BASE_BETA.to_f)
      expect(payload[:lorenz_state][:z_value]).to eq(telemetry_log.z_value.to_f)
      expect(payload[:tree_did]).to eq(tree.did)
      expect(payload[:telemetry_log_id]).to eq(telemetry_log.id)
      expect(payload[:created_at]).to eq(telemetry_log.created_at.iso8601(6))
      expect(payload[:timestamp]).to be_present
    end

    it "uses stub mode when CHAINLINK_FUNCTIONS_ROUTER is not set" do
      service = described_class.new(telemetry_log)

      allow(Rails.logger).to receive(:info).and_call_original
      expect(Rails.logger).to receive(:info).with(/Stub mode/).at_least(:once)

      request_id = service.dispatch!
      expect(request_id).to start_with("chainlink-req-")
    end
  end

  describe "#dispatch! edge cases" do
    let(:cluster_local) { create(:cluster) }
    let(:tree_local) { create(:tree, cluster: cluster_local) }
    let(:telemetry_log_local) do
      create(:telemetry_log, tree: tree_local,
        verified_by_iotex: true,
        z_value: 0.35,
        zk_proof_ref: "zk-proof-123")
    end

    it "generates a local stub request ID" do
      service = described_class.new(telemetry_log_local)
      request_id = service.dispatch!

      expect(request_id).to start_with("chainlink-req-")
      expect(telemetry_log_local.reload.chainlink_request_id).to eq(request_id)
      expect(telemetry_log_local.oracle_status).to eq("dispatched")
    end

    it "raises DispatchError when not verified by IoTeX" do
      telemetry_log_local.update_column(:verified_by_iotex, false)
      telemetry_log_local.reload
      service = described_class.new(telemetry_log_local)

      expect {
        service.dispatch!
      }.to raise_error(described_class::DispatchError, /не верифіковано/)
    end

    it "calls send_on_chain_request when env vars are present" do
      stub_const("ENV", ENV.to_h.merge(
        "CHAINLINK_FUNCTIONS_ROUTER" => "0x1234567890abcdef1234567890abcdef12345678",
        "CHAINLINK_SUBSCRIPTION_ID" => "42",
        "CHAINLINK_DON_ID" => "0x#{"d" * 64}",
        "ALCHEMY_POLYGON_RPC_URL" => "https://polygon-rpc.example.com",
        "ORACLE_PRIVATE_KEY" => "a" * 64
      ))

      service = described_class.new(telemetry_log_local)

      mock_client = double("Eth::Client")
      mock_key = double("Eth::Key")
      mock_contract = double("Eth::Contract")

      allow(Eth::Client).to receive(:create).and_return(mock_client)
      allow(Eth::Key).to receive(:new).and_return(mock_key)
      allow(Eth::Contract).to receive(:from_abi).and_return(mock_contract)
      allow(mock_client).to receive(:transact).and_return("0xtx_hash_123")

      request_id = service.dispatch!
      expect(request_id).to eq("0xtx_hash_123")
    end

    it "wraps on-chain errors in DispatchError" do
      stub_const("ENV", ENV.to_h.merge(
        "CHAINLINK_FUNCTIONS_ROUTER" => "0x1234567890abcdef1234567890abcdef12345678",
        "CHAINLINK_SUBSCRIPTION_ID" => "42",
        "CHAINLINK_DON_ID" => "0x#{"d" * 64}",
        "ALCHEMY_POLYGON_RPC_URL" => "https://polygon-rpc.example.com",
        "ORACLE_PRIVATE_KEY" => "a" * 64
      ))

      service = described_class.new(telemetry_log_local)

      allow(Eth::Client).to receive(:create).and_raise(StandardError, "RPC timeout")

      expect {
        service.dispatch!
      }.to raise_error(described_class::DispatchError, /Chainlink on-chain dispatch failed/)
    end

    it "raises DispatchError when WEB3_STRICT_MODE is true and credentials missing" do
      stub_const("ENV", ENV.to_h.merge(
        "WEB3_STRICT_MODE" => "true"
      ).except("CHAINLINK_FUNCTIONS_ROUTER", "CHAINLINK_SUBSCRIPTION_ID"))

      service = described_class.new(telemetry_log_local)

      expect {
        service.dispatch!
      }.to raise_error(described_class::DispatchError, /WEB3_STRICT_MODE/)
    end

    it "uses stub mode when WEB3_STRICT_MODE is not true" do
      stub_const("ENV", ENV.to_h.merge(
        "WEB3_STRICT_MODE" => "false"
      ).except("CHAINLINK_FUNCTIONS_ROUTER", "CHAINLINK_SUBSCRIPTION_ID"))

      service = described_class.new(telemetry_log_local)
      request_id = service.dispatch!

      expect(request_id).to start_with("chainlink-req-")
    end

    it "raises DispatchError when CHAINLINK_DON_ID is missing in on-chain mode" do
      stub_const("ENV", ENV.to_h.merge(
        "CHAINLINK_FUNCTIONS_ROUTER" => "0x1234567890abcdef1234567890abcdef12345678",
        "CHAINLINK_SUBSCRIPTION_ID" => "42",
        "ALCHEMY_POLYGON_RPC_URL" => "https://polygon-rpc.example.com",
        "ORACLE_PRIVATE_KEY" => "a" * 64
      ).except("CHAINLINK_DON_ID"))

      service = described_class.new(telemetry_log_local)

      mock_client = double("Eth::Client")
      mock_key = double("Eth::Key")
      mock_contract = double("Eth::Contract")

      allow(Web3::RpcConnectionPool).to receive(:client_for).and_return(mock_client)
      allow(Eth::Key).to receive(:new).and_return(mock_key)
      allow(Eth::Contract).to receive(:from_abi).and_return(mock_contract)

      expect {
        service.dispatch!
      }.to raise_error(described_class::DispatchError, /CHAINLINK_DON_ID/)
    end

    it "builds payload with nil z_value without crashing" do
      telemetry_log_local.update_column(:z_value, nil)
      telemetry_log_local.reload
      service = described_class.new(telemetry_log_local)

      payload = service.send(:build_chainlink_payload)
      expect(payload[:lorenz_state][:z_value]).to eq(0.0)
    end

    it "builds payload with nil peaq_did" do
      tree_local.update_column(:peaq_did, nil)
      tree_local.reload
      service = described_class.new(telemetry_log_local)

      payload = service.send(:build_chainlink_payload)
      expect(payload[:peaq_did]).to be_nil
    end

    it "builds payload with nil zk_proof_ref" do
      telemetry_log_local.update_column(:zk_proof_ref, nil)
      telemetry_log_local.reload
      service = described_class.new(telemetry_log_local)

      payload = service.send(:build_chainlink_payload)
      expect(payload[:zk_proof_ref]).to be_nil
    end

    it "includes created_at in ISO8601 format for partition pruning" do
      service = described_class.new(telemetry_log_local)
      payload = service.send(:build_chainlink_payload)

      expect(payload[:created_at]).to match(/\d{4}-\d{2}-\d{2}T/)
    end
  end

  describe "functions_router_abi" do
    it "returns valid JSON ABI structure" do
      service = described_class.new(telemetry_log)
      abi_json = service.send(:functions_router_abi)

      abi = JSON.parse(abi_json)
      expect(abi).to be_an(Array)
      expect(abi.first["name"]).to eq("sendRequest")
      expect(abi.first["type"]).to eq("function")
      expect(abi.first["inputs"].size).to eq(5)
    end

    it "includes all required Chainlink Functions Router v1 parameters" do
      service = described_class.new(telemetry_log)
      abi = JSON.parse(service.send(:functions_router_abi))

      input_names = abi.first["inputs"].map { |i| i["name"] }
      expect(input_names).to contain_exactly(
        "subscriptionId", "data", "dataVersion", "callbackGasLimit", "donId"
      )
    end
  end
end
