# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChainAuditService do
  before do
    silence_broadcasts!(:wallet_balance)
    ENV["ALCHEMY_POLYGON_RPC_URL"] ||= "https://polygon-rpc.example.com"
    ENV["CARBON_COIN_CONTRACT_ADDRESS"] ||= "0x#{'0' * 40}"
  end

  describe ".call" do
    let(:chain_total_raw) { 0 }

    before do
      # Стабуємо Web3 виклики
      mock_client = instance_double(Eth::Client)
      allow(Eth::Client).to receive(:create).and_return(mock_client)
      allow(Eth::Contract).to receive(:from_abi).and_return(instance_double(Eth::Contract))
      allow(mock_client).to receive(:call).and_return(chain_total_raw)
    end

    context "when DB and chain totals match" do
      let(:chain_total_raw) { 0 }

      it "returns non-critical result with zero delta" do
        result = described_class.call

        expect(result.db_total).to eq(0.0)
        expect(result.chain_total).to eq(0.0)
        expect(result.delta).to eq(0.0)
        expect(result.critical).to be false
        expect(result.checked_at).to be_present
      end
    end

    context "when DB has confirmed SCC transactions" do
      let(:chain_total_raw) { 500 * (10**18) }

      before do
        tree = create(:tree)
        wallet = tree.wallet
        wallet.update!(crypto_public_address: "0x#{'a' * 40}")

        wallet.blockchain_transactions.create!(
          amount: 500,
          token_type: :carbon_coin,
          status: :confirmed,
          to_address: wallet.crypto_public_address,
          tx_hash: "0x#{'a' * 64}"
        )

        # Транзакції, що повинні бути відфільтровані (pending статус або інший тип токена)
        wallet.blockchain_transactions.create!(
          amount: 100,
          token_type: :carbon_coin,
          status: :pending,
          to_address: wallet.crypto_public_address
        )

        wallet.blockchain_transactions.create!(
          amount: 200,
          token_type: :forest_coin,
          status: :confirmed,
          to_address: wallet.crypto_public_address,
          tx_hash: "0x#{'b' * 64}"
        )
      end

      it "sums only confirmed carbon_coin transactions" do
        result = described_class.call

        expect(result.db_total).to eq(500.0)
        expect(result.chain_total).to eq(500.0)
        expect(result.delta).to eq(0.0)
        expect(result.critical).to be false
      end
    end

    context "when a slash burned SCC [G4]" do
      # on-chain: 1000 minted − 300 slashed = 700 totalSupply
      let(:chain_total_raw) { 700 * (10**18) }

      before do
        tree = create(:tree)
        wallet = tree.wallet
        wallet.update!(crypto_public_address: "0x#{'d' * 40}")
        naas = create(:naas_contract, cluster: tree.cluster)

        # Mint: 1000 SCC (no sourceable) — counts as emission
        wallet.blockchain_transactions.create!(
          amount: 1000, token_type: :carbon_coin, status: :confirmed,
          to_address: wallet.crypto_public_address, tx_hash: "0x#{'d' * 64}"
        )
        # Slash-intent: 300 SCC (sourceable NaasContract) — a burn, must SUBTRACT
        wallet.blockchain_transactions.create!(
          amount: 300, token_type: :carbon_coin, status: :confirmed,
          sourceable: naas, direction: :burn, to_address: wallet.crypto_public_address, tx_hash: "0x#{'e' * 64}"
        )
      end

      it "subtracts confirmed slash-intents so db mirrors totalSupply (no false critical)" do
        result = described_class.call

        expect(result.db_total).to eq(700.0)   # 1000 − 300, NOT 1300
        expect(result.chain_total).to eq(700.0)
        expect(result.delta).to eq(0.0)
        expect(result.critical).to be false
      end
    end

    context "when delta exceeds threshold" do
      let(:chain_total_raw) { 1000 * (10**18) }

      before do
        tree = create(:tree)
        wallet = tree.wallet
        wallet.update!(crypto_public_address: "0x#{'c' * 40}")

        wallet.blockchain_transactions.create!(
          amount: 999,
          token_type: :carbon_coin,
          status: :confirmed,
          to_address: wallet.crypto_public_address,
          tx_hash: "0x#{'c' * 64}"
        )
      end

      it "marks result as critical" do
        result = described_class.call

        expect(result.db_total).to eq(999.0)
        expect(result.chain_total).to eq(1000.0)
        expect(result.delta).to eq(1.0)
        expect(result.critical).to be true
      end
    end

    context "when delta is exactly at threshold" do
      let(:chain_total_raw) { (0.0001 * (10**18)).to_i }

      it "is not critical when delta equals threshold" do
        result = described_class.call

        expect(result.delta).to be <= 0.0001 + Float::EPSILON
        expect(result.critical).to be false
      end
    end
  end

  describe "error handling" do
    context "when compute_audit raises an error" do
      before do
        allow(Rails.cache).to receive(:fetch).and_raise(StandardError, "DB connection lost")
      end

      it "returns fallback Result with zero values" do
        result = described_class.call

        expect(result.db_total).to eq(0)
        expect(result.chain_total).to eq(0)
        expect(result.delta).to eq(0)
        expect(result.critical).to be false
        expect(result.checked_at).to be_present
      end
    end
  end
end
