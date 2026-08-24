# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Treasury::MintBatchCollectorService do
  before do
    ENV["ALCHEMY_POLYGON_RPC_URL"] ||= "https://polygon-rpc.example.com"
    ENV["ORACLE_MINTER_PRIVATE_KEY"] ||= "0x" + "a" * 64
    ENV["CARBON_COIN_CONTRACT_ADDRESS"] ||= "0x" + "0" * 40
    ENV["FOREST_COIN_CONTRACT_ADDRESS"] ||= "0x" + "1" * 40
    ENV["DAO_TREASURY_ADDRESS"] ||= "0x" + "9" * 40

    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    allow(BlockchainConfirmationWorker).to receive(:perform_in)

    allow(Eth::Client).to receive(:create).and_return(mock_client)
    allow(Eth::Key).to receive(:new).and_return(mock_key)
    allow(Eth::Contract).to receive(:from_abi).and_return(mock_contract)
    allow(mock_client).to receive_messages(get_balance: 1 * 10**18, transact: fake_tx_hash, call: 0)

    unless defined?(Kredis)
      kredis_mod = Module.new do
        def self.lock(*, **, &block)
          block&.call
        end
      end
      stub_const("Kredis", kredis_mod)
    end
    allow(Kredis).to receive(:lock).and_yield

    Web3::RpcConnectionPool.reset!
    Rails.cache.clear
  end

  let(:fake_tx_hash) { "0x" + "f" * 64 }
  let(:mock_client) { instance_double(Eth::Client) }
  let(:mock_key) { instance_double(Eth::Key, address: "0x" + "d" * 40) }
  let(:mock_contract) { instance_double(Eth::Contract) }

  describe ".call" do
    context "when no pending transactions exist" do
      it "returns early without calling BlockchainMintingService" do
        allow(BlockchainMintingService).to receive(:call_batch)
        described_class.call
        expect(BlockchainMintingService).not_to have_received(:call_batch)
      end
    end

    context "with pending transactions above threshold" do
      let!(:tree) { create(:tree) }
      let!(:wallet) do
        tree.wallet.tap do |w|
          w.update!(crypto_public_address: "0x" + "b" * 40, hadron_kyc_status: "approved")
        end
      end

      let!(:transactions) do
        6.times.map do
          wallet.blockchain_transactions.create!(
            amount: 100,
            token_type: :carbon_coin,
            status: :pending,
            to_address: wallet.crypto_public_address,
            blockchain_network: "evm",
            locked_points: 1000
          )
        end
      end

      it "dispatches batch minting for transactions above threshold" do
        allow(BlockchainMintingService).to receive(:call_batch)
          .with(array_including(*transactions.map(&:id)), created_at_span: all(be_a(Time)).and(be_present))
        described_class.call
        expect(BlockchainMintingService).to have_received(:call_batch)
          .with(array_including(*transactions.map(&:id)), created_at_span: all(be_a(Time)).and(be_present))
      end

      it "sends all transactions in a single batch" do
        allow(BlockchainMintingService).to receive(:call_batch)
        described_class.call
        expect(BlockchainMintingService).to have_received(:call_batch).once
      end
    end

    context "with pending transactions below threshold" do
      let!(:tree) { create(:tree) }
      let!(:wallet) do
        tree.wallet.tap do |w|
          w.update!(crypto_public_address: "0x" + "b" * 40, hadron_kyc_status: "approved")
        end
      end

      let!(:transactions) do
        3.times.map do
          wallet.blockchain_transactions.create!(
            amount: 100,
            token_type: :carbon_coin,
            status: :pending,
            to_address: wallet.crypto_public_address,
            blockchain_network: "evm",
            locked_points: 1000
          )
        end
      end

      it "does not dispatch when below minimum batch size" do
        allow(BlockchainMintingService).to receive(:call_batch)
        described_class.call
        expect(BlockchainMintingService).not_to have_received(:call_batch)
      end
    end

    context "with old pending transactions below threshold" do
      let!(:tree) { create(:tree) }
      let!(:wallet) do
        tree.wallet.tap do |w|
          w.update!(crypto_public_address: "0x" + "b" * 40, hadron_kyc_status: "approved")
        end
      end

      let!(:transactions) do
        2.times.map do
          wallet.blockchain_transactions.create!(
            amount: 100,
            token_type: :carbon_coin,
            status: :pending,
            to_address: wallet.crypto_public_address,
            blockchain_network: "evm",
            locked_points: 1000,
            created_at: 45.minutes.ago
          )
        end
      end

      it "dispatches urgent transactions even below threshold" do
        allow(BlockchainMintingService).to receive(:call_batch)
          .with(array_including(*transactions.map(&:id)), created_at_span: all(be_a(Time)).and(be_present))
        described_class.call
        expect(BlockchainMintingService).to have_received(:call_batch)
          .with(array_including(*transactions.map(&:id)), created_at_span: all(be_a(Time)).and(be_present))
      end
    end

    context "with mixed token types" do
      let!(:tree) { create(:tree) }
      let!(:wallet) do
        tree.wallet.tap do |w|
          w.update!(crypto_public_address: "0x" + "b" * 40, hadron_kyc_status: "approved")
        end
      end

      let!(:carbon_txs) do
        6.times.map do
          wallet.blockchain_transactions.create!(
            amount: 100,
            token_type: :carbon_coin,
            status: :pending,
            to_address: wallet.crypto_public_address,
            blockchain_network: "evm",
            locked_points: 1000
          )
        end
      end

      let!(:forest_txs) do
        6.times.map do
          wallet.blockchain_transactions.create!(
            amount: 50,
            token_type: :forest_coin,
            status: :pending,
            to_address: wallet.crypto_public_address,
            blockchain_network: "evm",
            locked_points: 500
          )
        end
      end

      it "dispatches separate batches per token type" do
        allow(BlockchainMintingService).to receive(:call_batch)
        described_class.call
        expect(BlockchainMintingService).to have_received(:call_batch).twice
      end
    end
  end
end
