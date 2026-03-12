# frozen_string_literal: true

require "rails_helper"

RSpec.describe BlockchainConfirmationWorker, type: :worker do
  let(:wallet) { create(:wallet) }
  let(:tx_hash) { "0x" + SecureRandom.hex(32) }
  let!(:transaction) do
    create(:blockchain_transaction, wallet: wallet, tx_hash: tx_hash, status: :sent)
  end

  let(:client_double) { instance_double(Eth::Client) }

  before do
    allow(Web3::RpcConnectionPool).to receive(:client_for).with("ALCHEMY_POLYGON_RPC_URL").and_return(client_double)
  end

  describe "#perform" do
    context "when receipt confirms success (0x1)" do
      before do
        allow(client_double).to receive(:eth_get_transaction_receipt).and_return(
          { "result" => { "status" => "0x1" } }
        )
      end

      it "confirms the blockchain transaction" do
        described_class.new.perform(tx_hash)

        transaction.reload
        expect(transaction.status).to eq("confirmed")
      end

      it "confirms all transactions with matching tx_hash" do
        tx2 = create(:blockchain_transaction, wallet: wallet, tx_hash: tx_hash, status: :sent)

        described_class.new.perform(tx_hash)

        expect(transaction.reload.status).to eq("confirmed")
        expect(tx2.reload.status).to eq("confirmed")
      end
    end

    context "when receipt shows revert" do
      before do
        allow(client_double).to receive(:eth_get_transaction_receipt).and_return(
          { "result" => { "status" => "0x0" } }
        )
      end

      it "fails the transaction with EVM revert reason" do
        described_class.new.perform(tx_hash)

        transaction.reload
        expect(transaction.status).to eq("failed")
        expect(transaction.error_message).to include("EVM Revert")
      end
    end

    context "when receipt is not yet available" do
      before do
        allow(client_double).to receive(:eth_get_transaction_receipt).and_return(nil)
      end

      it "raises to trigger Sidekiq retry (polling)" do
        expect { described_class.new.perform(tx_hash) }.to raise_error(RuntimeError, /Очікування підтвердження/)
      end
    end

    context "when receipt exists but result is nil" do
      before do
        allow(client_double).to receive(:eth_get_transaction_receipt).and_return({})
      end

      it "raises to trigger Sidekiq retry" do
        expect { described_class.new.perform(tx_hash) }.to raise_error(RuntimeError, /Очікування підтвердження/)
      end
    end

    context "when tx_hash has no matching transactions" do
      before do
        allow(client_double).to receive(:eth_get_transaction_receipt).and_return(
          { "result" => { "status" => "0x1" } }
        )
      end

      it "returns early for unknown hash" do
        transaction.destroy!

        # Should not raise
        expect { described_class.new.perform(tx_hash) }.not_to raise_error
      end
    end
  end
end
