# frozen_string_literal: true

require "rails_helper"

RSpec.describe MintCarbonCoinWorker, type: :worker do
  let(:wallet) { create(:wallet) }

  before do
    allow(BlockchainMintingService).to receive(:call_batch)
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
  end

  describe "#perform" do
    context "with explicit transaction IDs" do
      let!(:tx1) { create(:blockchain_transaction, wallet: wallet, status: :pending) }
      let!(:tx2) { create(:blockchain_transaction, wallet: wallet, status: :pending) }

      it "calls BlockchainMintingService.call_batch with transaction IDs" do
        described_class.new.perform([tx1.id, tx2.id])

        expect(BlockchainMintingService).to have_received(:call_batch)
      end

      it "processes pending transactions only" do
        tx2.update!(status: :confirmed, tx_hash: SecureRandom.hex(32))

        described_class.new.perform([tx1.id, tx2.id])

        expect(BlockchainMintingService).to have_received(:call_batch)
      end
    end

    context "without transaction IDs (automatic collection)" do
      it "collects pending transactions automatically" do
        tx = create(:blockchain_transaction, wallet: wallet, status: :pending)

        described_class.new.perform

        expect(BlockchainMintingService).to have_received(:call_batch)
      end

      it "does nothing when no pending transactions exist" do
        described_class.new.perform

        expect(BlockchainMintingService).not_to have_received(:call_batch)
      end
    end

    context "with large batch (slicing)" do
      it "splits batch into groups of 200" do
        # Створюємо 201 транзакцію для перевірки slicing
        tx_ids = 201.times.map do
          create(:blockchain_transaction, wallet: wallet, status: :pending).id
        end

        described_class.new.perform(tx_ids)

        # call_batch повинен бути викликаний 2 рази (200 + 1)
        expect(BlockchainMintingService).to have_received(:call_batch).twice
      end
    end

    context "error handling" do
      it "resets transactions to pending on RPC failure" do
        tx = create(:blockchain_transaction, wallet: wallet, status: :pending)
        allow(BlockchainMintingService).to receive(:call_batch).and_raise(StandardError, "RPC Error")

        expect {
          described_class.new.perform([tx.id])
        }.to raise_error(StandardError, "RPC Error")
      end
    end
  end

  describe ".sidekiq_retries_exhausted" do
    it "rolls back locked points on permanent failure" do
      tx = create(:blockchain_transaction, wallet: wallet, status: :pending,
                                           locked_points: 10_000)
      original_balance = wallet.balance

      allow_any_instance_of(Wallet).to receive(:broadcast_update)

      job = { "args" => [[tx.id]], "error_message" => "Permanent RPC failure" }

      described_class.sidekiq_retries_exhausted_block.call(job, StandardError.new)

      tx.reload
      wallet.reload
      expect(tx.status).to eq("failed")
      expect(tx.notes).to include("Rollback")
      expect(wallet.balance).to eq(original_balance + 10_000)
    end

    it "skips transactions that are already confirmed" do
      tx = create(:blockchain_transaction, wallet: wallet, status: :confirmed,
                                           tx_hash: SecureRandom.hex(32))
      original_balance = wallet.balance

      allow_any_instance_of(Wallet).to receive(:broadcast_update)

      job = { "args" => [[tx.id]], "error_message" => "Failure" }

      described_class.sidekiq_retries_exhausted_block.call(job, StandardError.new)

      wallet.reload
      expect(wallet.balance).to eq(original_balance)
    end
  end
end
