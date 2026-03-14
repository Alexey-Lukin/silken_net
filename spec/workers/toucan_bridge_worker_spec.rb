# frozen_string_literal: true

require "rails_helper"

RSpec.describe ToucanBridgeWorker, type: :worker do
  let(:organization) { create(:organization, crypto_public_address: "0x#{'b' * 40}") }
  let(:cluster)      { create(:cluster, organization: organization) }
  let(:tree)         { create(:tree, cluster: cluster) }
  let(:wallet)       { tree.wallet }
  let(:fake_tx_hash) { "0x#{'f' * 64}" }

  before do
    allow_any_instance_of(Wallet).to receive(:broadcast_balance_update)
    allow_any_instance_of(Tree).to receive(:broadcast_map_update)
    allow(Toucan::BridgeService).to receive(:call).and_return(fake_tx_hash)
    allow(BlockchainConfirmationWorker).to receive(:perform_in)
  end

  describe "#perform" do
    context "with successful bridge" do
      let!(:tx) do
        wallet.update!(balance: 5000, locked_balance: 500)
        create(:blockchain_transaction,
               wallet: wallet,
               status: :pending,
               token_type: :carbon_coin,
               locked_points: 500,
               notes: "Bridging to Toucan Protocol (TCO2)")
      end

      it "calls Toucan::BridgeService with the transaction ID" do
        described_class.new.perform(tx.id)

        expect(Toucan::BridgeService).to have_received(:call).with(tx.id)
      end

      it "marks the transaction as sent with tx_hash" do
        described_class.new.perform(tx.id)

        tx.reload
        expect(tx.status).to eq("sent")
        expect(tx.tx_hash).to eq(fake_tx_hash)
      end

      it "deducts locked_points from locked_balance" do
        described_class.new.perform(tx.id)

        wallet.reload
        expect(wallet.locked_balance).to eq(0)
      end

      it "adds locked_points to toucan_bridged_balance" do
        described_class.new.perform(tx.id)

        wallet.reload
        expect(wallet.toucan_bridged_balance).to eq(500)
      end

      it "schedules BlockchainConfirmationWorker in 30 seconds" do
        described_class.new.perform(tx.id)

        expect(BlockchainConfirmationWorker).to have_received(:perform_in).with(30.seconds, fake_tx_hash)
      end
    end

    context "when transaction is not found" do
      it "logs an error and does not raise" do
        expect(Rails.logger).to receive(:error).with(/не знайдено/)

        expect {
          described_class.new.perform(-1)
        }.not_to raise_error
      end
    end

    context "when bridge service raises an RPC error" do
      let!(:tx) do
        wallet.update!(balance: 5000, locked_balance: 500)
        create(:blockchain_transaction,
               wallet: wallet,
               status: :pending,
               token_type: :carbon_coin,
               locked_points: 500,
               notes: "Bridging to Toucan Protocol (TCO2)")
      end

      it "re-raises the error for Sidekiq retry" do
        allow(Toucan::BridgeService).to receive(:call).and_raise(HTTPX::TimeoutError.new(nil, "timeout"))

        expect {
          described_class.new.perform(tx.id)
        }.to raise_error(HTTPX::TimeoutError)
      end
    end

    it "uses web3_critical queue" do
      expect(described_class.sidekiq_options["queue"]).to eq("web3_critical")
    end

    it "has retry set to 5" do
      expect(described_class.sidekiq_options["retry"]).to eq(5)
    end
  end
end
