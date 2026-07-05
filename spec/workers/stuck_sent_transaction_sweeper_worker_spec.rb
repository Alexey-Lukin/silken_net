# frozen_string_literal: true

require "rails_helper"

RSpec.describe StuckSentTransactionSweeperWorker, type: :worker do
  let(:wallet) { create(:wallet) }

  def sent_tx(sent_ago:, created_ago: sent_ago, tx_hash: "0x#{SecureRandom.hex(32)}")
    create(:blockchain_transaction, wallet: wallet, status: :sent,
                                    tx_hash: tx_hash, created_at: created_ago,
                                    sent_at: sent_ago)
  end

  describe "#perform" do
    it "re-arms confirmation for a tx stuck in :sent past the threshold" do
      tx = sent_tx(sent_ago: 20.minutes.ago)
      expect(BlockchainConfirmationWorker).to receive(:perform_async).with(tx.tx_hash, kind_of(String))
      described_class.new.perform
    end

    it "ignores a :sent tx still within the live-poller window" do
      sent_tx(sent_ago: 5.minutes.ago)
      expect(BlockchainConfirmationWorker).not_to receive(:perform_async)
      described_class.new.perform
    end

    it "ignores a stuck :sent tx on a non-EVM network (ConfirmationWorker is Polygon-specific)" do
      tx = sent_tx(sent_ago: 20.minutes.ago)
      tx.update_columns(blockchain_network: "solana")
      expect(BlockchainConfirmationWorker).not_to receive(:perform_async)
      described_class.new.perform
    end

    it "ignores terminal states (confirmed/failed) at any age" do
      create(:blockchain_transaction, wallet: wallet, status: :confirmed, created_at: 2.hours.ago)
      create(:blockchain_transaction, wallet: wallet, status: :failed, created_at: 2.hours.ago)
      expect(BlockchainConfirmationWorker).not_to receive(:perform_async)
      described_class.new.perform
    end

    it "keys on sent_at, NOT created_at (reset-to-pending keeps an old created_at)" do
      # A genuinely-stuck tx whose pending wait was long: created 3h ago, broadcast 20m ago.
      tx = sent_tx(sent_ago: 20.minutes.ago, created_ago: 3.hours.ago)
      expect(BlockchainConfirmationWorker).to receive(:perform_async).with(tx.tx_hash, kind_of(String))
      described_class.new.perform
    end

    it "dedups a batchMint (shared tx_hash) to one re-arm with the earliest created_at" do
      shared = "0x#{SecureRandom.hex(32)}"
      earliest = 40.minutes.ago
      sent_tx(sent_ago: 20.minutes.ago, created_ago: earliest, tx_hash: shared)
      sent_tx(sent_ago: 20.minutes.ago, created_ago: 25.minutes.ago, tx_hash: shared)

      expect(BlockchainConfirmationWorker).to receive(:perform_async)
        .with(shared, earliest.iso8601).once
      described_class.new.perform
    end

    it "skips a stuck :sent tx with a blank tx_hash (nothing to re-arm)" do
      tx = build(:blockchain_transaction, wallet: wallet, status: :sent, tx_hash: "0xtmp")
      tx.save!(validate: false)
      tx.update_columns(tx_hash: nil, sent_at: 20.minutes.ago)
      expect(BlockchainConfirmationWorker).not_to receive(:perform_async)
      described_class.new.perform
    end

    it "does not log when nothing is stuck (re_armed stays zero)" do
      sent_tx(sent_ago: 2.minutes.ago) # fresh → not swept
      expect(Rails.logger).not_to receive(:warn)
      described_class.new.perform
    end
  end
end
