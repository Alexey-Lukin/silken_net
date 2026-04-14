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
      tx = create(:blockchain_transaction, wallet: wallet, status: :pending, locked_points: 10_000, tx_hash: nil)

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
      tx = create(:blockchain_transaction, wallet: wallet, status: :confirmed, tx_hash: "0x#{SecureRandom.hex(32)}")
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

    it "skips transactions that are already failed" do
      tx = create(:blockchain_transaction, wallet: wallet, status: :failed, notes: "Previously failed")
      original_balance = wallet.balance
      original_locked = wallet.locked_balance

      described_class.call(
        telemetry_log_id: telemetry_log.id_value,
        created_at_iso: telemetry_log.created_at.iso8601(6)
      )

      wallet.reload
      tx.reload
      expect(wallet.balance).to eq(original_balance)
      expect(wallet.locked_balance).to eq(original_locked)
      expect(tx.notes).to eq("Previously failed")
    end

    it "handles partial locked_balance gracefully" do
      wallet.update!(balance: 20_000, locked_balance: 3_000)
      tx = create(:blockchain_transaction, wallet: wallet, status: :pending, locked_points: 10_000, tx_hash: nil)

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
      tx = create(:blockchain_transaction, wallet: wallet, status: :pending, locked_points: 5_000, tx_hash: nil)

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

  describe "broadcast_update after rollback" do
    it "calls broadcast_update on wallet when method is available" do
      wallet.update!(balance: 20_000, locked_balance: 10_000)
      tx = create(:blockchain_transaction, wallet: wallet, status: :pending, locked_points: 10_000, tx_hash: nil)

      expect_any_instance_of(Wallet).to receive(:broadcast_update).at_least(:once)

      described_class.call(transactions: BlockchainTransaction.where(id: tx.id))
    end
  end

  # =========================================================================
  # DOUBLE-SPEND GUARD (tx_hash present → manual_review)
  # =========================================================================
  describe "double-spend protection" do
    let!(:telemetry_log) { create(:telemetry_log, :verified_telemetry, tree: tree) }

    context "when transaction has tx_hash (was sent to mempool)" do
      it "escalates to manual_review when receipt is pending (null)" do
        wallet.update!(balance: 20_000, locked_balance: 10_000)
        tx = create(:blockchain_transaction, wallet: wallet, status: :sent,
                    tx_hash: "0x" + SecureRandom.hex(32), locked_points: 10_000)

        # Mock RPC to return nil receipt (transaction pending in mempool)
        mock_client = instance_double(Eth::Client)
        allow(Web3::RpcConnectionPool).to receive(:client_for).and_return(mock_client)
        allow(mock_client).to receive(:eth_get_transaction_receipt).and_return(nil)

        described_class.call(transactions: BlockchainTransaction.where(id: tx.id))

        tx.reload
        wallet.reload
        expect(tx.status).to eq("manual_review")
        expect(wallet.locked_balance).to eq(10_000) # Funds remain locked!
      end

      it "does NOT rollback when receipt shows confirmed on-chain" do
        wallet.update!(balance: 20_000, locked_balance: 10_000)
        tx = create(:blockchain_transaction, wallet: wallet, status: :sent,
                    tx_hash: "0x" + SecureRandom.hex(32), locked_points: 10_000)

        # Mock RPC to return confirmed receipt
        mock_client = instance_double(Eth::Client)
        allow(Web3::RpcConnectionPool).to receive(:client_for).and_return(mock_client)
        allow(mock_client).to receive(:eth_get_transaction_receipt)
          .and_return({ "status" => "0x1", "blockNumber" => "0x123" })

        described_class.call(transactions: BlockchainTransaction.where(id: tx.id))

        tx.reload
        wallet.reload
        expect(tx.status).to eq("confirmed")
        expect(wallet.locked_balance).to eq(10_000) # Not released — confirmed on-chain
      end

      it "performs rollback when receipt shows reverted" do
        wallet.update!(balance: 20_000, locked_balance: 10_000)
        tx = create(:blockchain_transaction, wallet: wallet, status: :sent,
                    tx_hash: "0x" + SecureRandom.hex(32), locked_points: 10_000)

        # Mock RPC to return reverted receipt
        mock_client = instance_double(Eth::Client)
        allow(Web3::RpcConnectionPool).to receive(:client_for).and_return(mock_client)
        allow(mock_client).to receive(:eth_get_transaction_receipt)
          .and_return({ "status" => "0x0" })

        described_class.call(transactions: BlockchainTransaction.where(id: tx.id))

        tx.reload
        wallet.reload
        expect(tx.status).to eq("failed")
        expect(wallet.locked_balance).to eq(0) # Safely released
      end

      it "escalates to manual_review when RPC throws error" do
        wallet.update!(balance: 20_000, locked_balance: 10_000)
        tx = create(:blockchain_transaction, wallet: wallet, status: :sent,
                    tx_hash: "0x" + SecureRandom.hex(32), locked_points: 10_000)

        # Mock RPC to raise timeout
        mock_client = instance_double(Eth::Client)
        allow(Web3::RpcConnectionPool).to receive(:client_for).and_return(mock_client)
        allow(mock_client).to receive(:eth_get_transaction_receipt).and_raise(Net::ReadTimeout)

        described_class.call(transactions: BlockchainTransaction.where(id: tx.id))

        tx.reload
        wallet.reload
        expect(tx.status).to eq("manual_review")
        expect(wallet.locked_balance).to eq(10_000) # Funds remain locked!
      end
    end

    context "when transaction has NO tx_hash (never sent to mempool)" do
      it "safely rolls back and releases funds" do
        wallet.update!(balance: 20_000, locked_balance: 10_000)
        tx = create(:blockchain_transaction, wallet: wallet, status: :pending,
                    tx_hash: nil, locked_points: 10_000)

        described_class.call(transactions: BlockchainTransaction.where(id: tx.id))

        tx.reload
        wallet.reload
        expect(tx.status).to eq("failed")
        expect(wallet.locked_balance).to eq(0)
      end
    end

    it "skips transactions already in manual_review" do
      wallet.update!(balance: 20_000, locked_balance: 10_000)
      tx = create(:blockchain_transaction, wallet: wallet, status: :manual_review,
                  tx_hash: "0x" + SecureRandom.hex(32), locked_points: 10_000)

      original_locked = wallet.locked_balance

      described_class.call(transactions: BlockchainTransaction.where(id: tx.id))

      wallet.reload
      expect(wallet.locked_balance).to eq(original_locked)
    end
  end
end
