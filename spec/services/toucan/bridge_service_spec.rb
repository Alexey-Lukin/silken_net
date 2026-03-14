# frozen_string_literal: true

require "rails_helper"

RSpec.describe Toucan::BridgeService do
  let(:organization) { create(:organization, crypto_public_address: "0x#{'b' * 40}") }
  let(:cluster)      { create(:cluster, organization: organization) }
  let(:tree)         { create(:tree, cluster: cluster) }
  let(:wallet)       { tree.wallet }
  let(:tx) do
    create(:blockchain_transaction,
           wallet: wallet,
           status: :pending,
           token_type: :carbon_coin,
           locked_points: 500,
           notes: "Bridging to Toucan Protocol (TCO2)")
  end

  let(:mock_client)   { instance_double(Eth::Client) }
  let(:mock_key)      { instance_double(Eth::Key, address: "0x#{'d' * 40}") }
  let(:mock_contract) { double("contract") }
  let(:fake_tx_hash)  { "0x#{'f' * 64}" }

  before do
    ENV["ALCHEMY_POLYGON_RPC_URL"] ||= "https://polygon-rpc.example.com"
    ENV["ORACLE_PRIVATE_KEY"] ||= "0x#{'a' * 64}"
    ENV["TOUCAN_BRIDGE_CONTRACT_ADDRESS"] ||= "0x#{'c' * 40}"
    ENV["CARBON_COIN_CONTRACT_ADDRESS"] ||= "0x#{'0' * 40}"

    allow(Eth::Client).to receive(:create).and_return(mock_client)
    allow(Eth::Key).to receive(:new).and_return(mock_key)
    allow(Eth::Contract).to receive(:from_abi).and_return(mock_contract)
    allow(mock_client).to receive(:transact).and_return(fake_tx_hash)
    allow_any_instance_of(Wallet).to receive(:broadcast_balance_update)
    allow_any_instance_of(Tree).to receive(:broadcast_map_update)
  end

  describe ".call" do
    it "returns a transaction hash" do
      result = described_class.call(tx.id)

      expect(result).to eq(fake_tx_hash)
    end

    it "connects to Polygon RPC via connection pool" do
      described_class.call(tx.id)

      expect(Eth::Client).to have_received(:create)
    end

    it "calls deposit on the Toucan Bridge contract" do
      described_class.call(tx.id)

      expect(mock_client).to have_received(:transact).with(
        mock_contract, "deposit",
        ENV.fetch("CARBON_COIN_CONTRACT_ADDRESS"),
        Web3::WeiConverter.to_wei(tx.locked_points),
        sender_key: mock_key, legacy: false
      )
    end

    it "raises ActiveRecord::RecordNotFound for invalid transaction ID" do
      expect { described_class.call(-1) }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
