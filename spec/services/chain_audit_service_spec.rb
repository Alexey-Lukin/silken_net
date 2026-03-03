# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChainAuditService do
  before do
    allow_any_instance_of(Wallet).to receive(:broadcast_balance_update)
  end

  describe ".call" do
    let(:chain_total_raw) { 0 }

    before do
      # Стабуємо Web3 виклики
      mock_client = instance_double(Eth::Client)
      allow(Eth::Client).to receive(:create).and_return(mock_client)
      allow(Eth::Contract).to receive(:from_abi).and_return(double("contract"))
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

    context "when delta exceeds threshold" do
      let(:chain_total_raw) { 1000 * (10**18) }

      before do
        tree = create(:tree)
        wallet = tree.wallet

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
end
