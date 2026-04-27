# frozen_string_literal: true

require "rails_helper"

RSpec.describe Etherisc::ClaimService do
  let(:organization) { create(:organization, crypto_public_address: "0x" + "ab" * 20) }
  let(:cluster) { create(:cluster, organization: organization) }
  let(:insurance) do
    create(:parametric_insurance, :triggered,
           cluster: cluster,
           organization: organization,
           etherisc_policy_id: "42")
  end

  let(:mock_client) { instance_double(Eth::Client) }
  let(:mock_key) { instance_double(Eth::Key, address: "0x" + "00" * 20) }
  let(:mock_contract) { instance_double(Eth::Contract) }
  let(:fake_tx_hash) { "0x" + "fa" * 32 }

  before do
    allow(Web3::RpcConnectionPool).to receive(:client_for).and_return(mock_client)
    allow(Eth::Key).to receive(:new).and_return(mock_key)
    allow(Eth::Contract).to receive(:from_abi).and_return(mock_contract)
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("ORACLE_PRIVATE_KEY").and_return("0x" + "ff" * 32)
    allow(ENV).to receive(:fetch).with("ETHERISC_DIP_CONTRACT_ADDRESS").and_return("0x" + "ee" * 20)
    allow(mock_client).to receive(:transact).and_return(fake_tx_hash)
  end

  describe "#claim!" do
    it "sends triggerClaim transaction to Etherisc DIP contract" do
      result = described_class.new(insurance).claim!

      expect(mock_client).to have_received(:transact).with(
        mock_contract, "triggerClaim", 42,
        sender_key: mock_key, legacy: false
      )
      expect(result).to eq(fake_tx_hash)
    end

    it "connects to Polygon via RPC connection pool" do
      described_class.new(insurance).claim!

      expect(Web3::RpcConnectionPool).to have_received(:client_for).with("ALCHEMY_POLYGON_RPC_URL")
    end

    it "creates contract with Etherisc DIP address from ENV" do
      described_class.new(insurance).claim!

      expect(Eth::Contract).to have_received(:from_abi).with(
        name: "EtheriscDIP",
        address: "0x" + "ee" * 20,
        abi: described_class::ETHERISC_CLAIM_ABI
      )
    end

    it "converts etherisc_policy_id to integer for contract call" do
      insurance.update_column(:etherisc_policy_id, "12345")

      described_class.new(insurance).claim!

      expect(mock_client).to have_received(:transact).with(
        mock_contract, "triggerClaim", 12345,
        sender_key: mock_key, legacy: false
      )
    end

    it "raises on RPC failure for Sidekiq retry" do
      allow(mock_client).to receive(:transact).and_raise(StandardError, "RPC timeout")

      expect {
        described_class.new(insurance).claim!
      }.to raise_error(StandardError, "RPC timeout")
    end

    it "converts nil etherisc_policy_id to 0" do
      insurance.update_column(:etherisc_policy_id, nil)

      described_class.new(insurance).claim!

      expect(mock_client).to have_received(:transact).with(
        mock_contract, "triggerClaim", 0,
        sender_key: mock_key, legacy: false
      )
    end

    it "converts non-numeric policy_id to 0" do
      insurance.update_column(:etherisc_policy_id, "abc")

      described_class.new(insurance).claim!

      expect(mock_client).to have_received(:transact).with(
        mock_contract, "triggerClaim", 0,
        sender_key: mock_key, legacy: false
      )
    end

    it "returns a string tx_hash" do
      result = described_class.new(insurance).claim!
      expect(result).to be_a(String)
      expect(result).to start_with("0x")
    end

    it "raises KeyError when ORACLE_PRIVATE_KEY is not set" do
      allow(ENV).to receive(:fetch).with("ORACLE_PRIVATE_KEY").and_raise(KeyError, "key not found: \"ORACLE_PRIVATE_KEY\"")

      expect {
        described_class.new(insurance).claim!
      }.to raise_error(KeyError)
    end

    it "raises KeyError when ETHERISC_DIP_CONTRACT_ADDRESS is not set" do
      allow(ENV).to receive(:fetch).with("ETHERISC_DIP_CONTRACT_ADDRESS").and_raise(KeyError, "key not found: \"ETHERISC_DIP_CONTRACT_ADDRESS\"")

      expect {
        described_class.new(insurance).claim!
      }.to raise_error(KeyError)
    end
  end

  describe "ETHERISC_CLAIM_ABI" do
    it "is valid JSON" do
      abi = JSON.parse(described_class::ETHERISC_CLAIM_ABI)
      expect(abi).to be_an(Array)
      expect(abi.first["name"]).to eq("triggerClaim")
    end

    it "has correct function signature" do
      abi = JSON.parse(described_class::ETHERISC_CLAIM_ABI)
      func = abi.first
      expect(func["type"]).to eq("function")
      expect(func["stateMutability"]).to eq("nonpayable")
      expect(func["inputs"].size).to eq(1)
      expect(func["inputs"].first["type"]).to eq("uint256")
    end
  end
end
