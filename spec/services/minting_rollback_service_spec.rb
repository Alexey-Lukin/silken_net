# frozen_string_literal: true

require "rails_helper"

RSpec.describe MintingRollbackService do
  let(:organization) { create(:organization) }
  let(:cluster) { create(:cluster, organization: organization) }
  let(:tree) { create(:tree, cluster: cluster) }
  let(:wallet) { tree.wallet }

  before do
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    allow_any_instance_of(Wallet).to receive(:broadcast_update)
  end

  describe ".call with telemetry_log_id (oracle-driven flow)" do
    let!(:telemetry_log) { create(:telemetry_log, :verified_telemetry, tree: tree) }

    it "releases locked points on permanent failure" do
      wallet.update!(balance: 20_000, locked_balance: 10_000)
      tx = create(:blockchain_transaction, wallet: wallet, status: :pending, locked_points: 10_000)

      described_class.call(
        telemetry_log_id: telemetry_log.id_value,
        created_at_iso: telemetry_log.created_at.iso8601(6)
      )

      tx.reload
      wallet.reload
      expect(tx.status).to eq("failed")
      expect(tx.notes).to include("Rollback")
      expect(wallet.locked_balance).to eq(0)
    end

    it "skips transactions that are already confirmed" do
      tx = create(:blockchain_transaction, wallet: wallet, status: :confirmed, tx_hash: SecureRandom.hex(32))
      original_balance = wallet.balance
      original_locked = wallet.locked_balance

      described_class.call(
        telemetry_log_id: telemetry_log.id_value,
        created_at_iso: telemetry_log.created_at.iso8601(6)
      )

      wallet.reload
      expect(wallet.balance).to eq(original_balance)
      expect(wallet.locked_balance).to eq(original_locked)
    end

    it "handles partial locked_balance gracefully" do
      wallet.update!(balance: 20_000, locked_balance: 3_000)
      tx = create(:blockchain_transaction, wallet: wallet, status: :pending, locked_points: 10_000)

      described_class.call(
        telemetry_log_id: telemetry_log.id_value,
        created_at_iso: telemetry_log.created_at.iso8601(6)
      )

      tx.reload
      wallet.reload
      expect(tx.status).to eq("failed")
      expect(wallet.locked_balance).to eq(0)
    end

    it "does nothing when telemetry_log not found" do
      wallet.update!(balance: 20_000, locked_balance: 10_000)
      create(:blockchain_transaction, wallet: wallet, status: :pending, locked_points: 10_000)

      described_class.call(telemetry_log_id: -1, created_at_iso: Time.current.iso8601(6))

      wallet.reload
      expect(wallet.locked_balance).to eq(10_000)
    end

    it "does nothing when wallet is nil" do
      orphan_tree = create(:tree, cluster: cluster)
      orphan_tree.wallet.destroy!
      orphan_tree.reload

      log = create(:telemetry_log, :verified_telemetry, tree: orphan_tree)

      expect {
        described_class.call(telemetry_log_id: log.id_value, created_at_iso: log.created_at.iso8601(6))
      }.not_to raise_error
    end
  end

  describe ".call with transactions (auto-discovery flow)" do
    it "rolls back all provided pending/processing transactions" do
      wallet.update!(locked_balance: 5_000)
      tx = create(:blockchain_transaction, wallet: wallet, status: :pending, locked_points: 5_000)

      described_class.call(transactions: BlockchainTransaction.where(id: tx.id))

      tx.reload
      expect(tx.status).to eq("failed")
      expect(tx.notes).to include("Rollback")
    end

    it "does nothing when transactions are empty" do
      expect {
        described_class.call(transactions: BlockchainTransaction.none)
      }.not_to raise_error
    end
  end

  describe ".call with no arguments" do
    it "does nothing gracefully" do
      expect {
        described_class.call
      }.not_to raise_error
    end
  end
end
