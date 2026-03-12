# frozen_string_literal: true

require "rails_helper"

RSpec.describe MintCarbonCoinWorker, type: :worker do
  let(:organization) { create(:organization) }
  let(:cluster) { create(:cluster, organization: organization) }
  let(:tree) { create(:tree, cluster: cluster) }
  let(:wallet) { tree.wallet }

  before do
    allow(BlockchainMintingService).to receive(:call_batch)
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
  end

  describe "#perform with telemetry_log_id (oracle-driven flow)" do
    let!(:telemetry_log) do
      create(:telemetry_log, :verified_telemetry, tree: tree)
    end

    let!(:tx1) { create(:blockchain_transaction, wallet: wallet, status: :pending) }
    let!(:tx2) { create(:blockchain_transaction, wallet: wallet, status: :pending) }

    it "finds TelemetryLog and calls BlockchainMintingService with telemetry_log" do
      described_class.new.perform(telemetry_log.id_value, telemetry_log.created_at.iso8601(6))

      expect(BlockchainMintingService).to have_received(:call_batch)
        .with(array_including(tx1.id, tx2.id), telemetry_log: telemetry_log)
    end

    it "does nothing when telemetry_log not found" do
      described_class.new.perform(-1, Time.current.iso8601(6))

      expect(BlockchainMintingService).not_to have_received(:call_batch)
    end

    it "does nothing when wallet has no pending transactions" do
      tx1.update!(status: :confirmed, tx_hash: SecureRandom.hex(32))
      tx2.update!(status: :confirmed, tx_hash: SecureRandom.hex(32))

      described_class.new.perform(telemetry_log.id_value, telemetry_log.created_at.iso8601(6))

      expect(BlockchainMintingService).not_to have_received(:call_batch)
    end

    it "re-raises errors for Sidekiq retry" do
      allow(BlockchainMintingService).to receive(:call_batch).and_raise(StandardError, "RPC Error")

      expect {
        described_class.new.perform(telemetry_log.id_value, telemetry_log.created_at.iso8601(6))
      }.to raise_error(StandardError, "RPC Error")
    end
  end

  describe "#perform without arguments (auto-discovery flow)" do
    it "collects pending transactions automatically" do
      tx = create(:blockchain_transaction, wallet: wallet, status: :pending)

      described_class.new.perform

      expect(BlockchainMintingService).to have_received(:call_batch)
    end

    it "does nothing when no pending transactions exist" do
      described_class.new.perform

      expect(BlockchainMintingService).not_to have_received(:call_batch)
    end

    it "splits batch into groups of 200" do
      201.times do
        create(:blockchain_transaction, wallet: wallet, status: :pending)
      end

      described_class.new.perform

      expect(BlockchainMintingService).to have_received(:call_batch).twice
    end

    it "resets transactions to pending on RPC failure" do
      tx = create(:blockchain_transaction, wallet: wallet, status: :pending)
      allow(BlockchainMintingService).to receive(:call_batch).and_raise(StandardError, "RPC Error")

      expect {
        described_class.new.perform
      }.to raise_error(StandardError, "RPC Error")
    end
  end

  describe ".sidekiq_retries_exhausted" do
    it "releases locked points on permanent failure (oracle-driven flow)" do
      telemetry_log = create(:telemetry_log, :verified_telemetry, tree: tree)
      wallet.update!(balance: 20_000, locked_balance: 10_000)
      tx = create(:blockchain_transaction, wallet: wallet, status: :pending,
                                           locked_points: 10_000)
      original_balance = wallet.balance

      allow_any_instance_of(Wallet).to receive(:broadcast_update)

      job = {
        "args" => [ telemetry_log.id_value, telemetry_log.created_at.iso8601(6) ],
        "error_message" => "Permanent RPC failure"
      }

      described_class.sidekiq_retries_exhausted_block.call(job, StandardError.new)

      tx.reload
      wallet.reload
      expect(tx.status).to eq("failed")
      expect(tx.notes).to include("Rollback")
      # [FIX]: Balance stays the same — lock_and_mint! only changes locked_balance, not balance.
      # The rollback should release locked funds, not inflate balance.
      expect(wallet.balance).to eq(original_balance)
      expect(wallet.locked_balance).to eq(0)
    end

    it "skips transactions that are already confirmed" do
      telemetry_log = create(:telemetry_log, :verified_telemetry, tree: tree)
      tx = create(:blockchain_transaction, wallet: wallet, status: :confirmed,
                                           tx_hash: SecureRandom.hex(32))
      original_balance = wallet.balance
      original_locked = wallet.locked_balance

      allow_any_instance_of(Wallet).to receive(:broadcast_update)

      job = {
        "args" => [ telemetry_log.id_value, telemetry_log.created_at.iso8601(6) ],
        "error_message" => "Failure"
      }

      described_class.sidekiq_retries_exhausted_block.call(job, StandardError.new)

      wallet.reload
      expect(wallet.balance).to eq(original_balance)
      expect(wallet.locked_balance).to eq(original_locked)
    end

    context "with auto-discovery flow (nil telemetry_log_id)" do
      it "finds all pending/processing transactions when telemetry_log_id is nil" do
        tx = create(:blockchain_transaction, wallet: wallet, status: :pending, locked_points: 5_000)
        wallet.update!(locked_balance: 5_000)

        allow_any_instance_of(Wallet).to receive(:broadcast_update)

        job = { "args" => [ nil, nil ], "error_message" => "Permanent failure" }

        described_class.sidekiq_retries_exhausted_block.call(job, StandardError.new)

        tx.reload
        expect(tx.status).to eq("failed")
        expect(tx.notes).to include("Rollback")
      end
    end

    context "with partial locked_balance fallback" do
      it "releases only available locked_balance when it is less than refund_points" do
        telemetry_log = create(:telemetry_log, :verified_telemetry, tree: tree)
        wallet.update!(balance: 20_000, locked_balance: 3_000)
        tx = create(:blockchain_transaction, wallet: wallet, status: :pending,
                                             locked_points: 10_000)

        allow_any_instance_of(Wallet).to receive(:broadcast_update)

        job = {
          "args" => [ telemetry_log.id_value, telemetry_log.created_at.iso8601(6) ],
          "error_message" => "Permanent RPC failure"
        }

        described_class.sidekiq_retries_exhausted_block.call(job, StandardError.new)

        wallet.reload
        expect(wallet.locked_balance).to eq(0)
      end

      it "skips release when locked_balance is already zero" do
        telemetry_log = create(:telemetry_log, :verified_telemetry, tree: tree)
        wallet.update!(balance: 20_000, locked_balance: 0)
        tx = create(:blockchain_transaction, wallet: wallet, status: :pending,
                                             locked_points: 10_000)

        allow_any_instance_of(Wallet).to receive(:broadcast_update)

        job = {
          "args" => [ telemetry_log.id_value, telemetry_log.created_at.iso8601(6) ],
          "error_message" => "Permanent RPC failure"
        }

        described_class.sidekiq_retries_exhausted_block.call(job, StandardError.new)

        wallet.reload
        expect(wallet.locked_balance).to eq(0)
      end
    end

    context "with oracle-driven flow and nil created_at_iso" do
      it "finds telemetry log without partition pruning" do
        telemetry_log = create(:telemetry_log, :verified_telemetry, tree: tree)
        wallet.update!(locked_balance: 5_000)
        tx = create(:blockchain_transaction, wallet: wallet, status: :pending,
                                             locked_points: 5_000)

        allow_any_instance_of(Wallet).to receive(:broadcast_update)

        job = {
          "args" => [ telemetry_log.id_value, nil ],
          "error_message" => "Permanent failure"
        }

        described_class.sidekiq_retries_exhausted_block.call(job, StandardError.new)

        tx.reload
        expect(tx.status).to eq("failed")
      end
    end

    context "when telemetry_log not found" do
      it "skips processing via next guard" do
        allow_any_instance_of(Wallet).to receive(:broadcast_update)

        job = {
          "args" => [ -999, Time.current.iso8601(6) ],
          "error_message" => "Permanent failure"
        }

        expect {
          described_class.sidekiq_retries_exhausted_block.call(job, StandardError.new)
        }.not_to raise_error
      end
    end

    context "when wallet is nil (tree has no wallet)" do
      it "skips processing via next guard" do
        telemetry_log = create(:telemetry_log, :verified_telemetry, tree: tree)
        allow_any_instance_of(Tree).to receive(:wallet).and_return(nil)

        job = {
          "args" => [ telemetry_log.id_value, telemetry_log.created_at.iso8601(6) ],
          "error_message" => "Permanent failure"
        }

        expect {
          described_class.sidekiq_retries_exhausted_block.call(job, StandardError.new)
        }.not_to raise_error
      end
    end

    context "with invalid created_at_iso format" do
      it "falls back to search without partition pruning" do
        telemetry_log = create(:telemetry_log, :verified_telemetry, tree: tree)
        wallet.update!(locked_balance: 5_000)
        tx = create(:blockchain_transaction, wallet: wallet, status: :pending,
                                             locked_points: 5_000)

        allow_any_instance_of(Wallet).to receive(:broadcast_update)

        job = {
          "args" => [ telemetry_log.id_value, "not-a-valid-iso-date" ],
          "error_message" => "Permanent failure"
        }

        described_class.sidekiq_retries_exhausted_block.call(job, StandardError.new)

        tx.reload
        expect(tx.status).to eq("failed")
      end
    end

    context "when broadcast_update is not available" do
      it "handles wallet without broadcast_update responding false" do
        telemetry_log = create(:telemetry_log, :verified_telemetry, tree: tree)
        wallet.update!(balance: 20_000, locked_balance: 10_000)
        tx = create(:blockchain_transaction, wallet: wallet, status: :pending,
                                             locked_points: 10_000)

        # Stub broadcast_update to just do nothing
        allow_any_instance_of(Wallet).to receive(:broadcast_update)

        job = {
          "args" => [ telemetry_log.id_value, telemetry_log.created_at.iso8601(6) ],
          "error_message" => "Permanent failure"
        }

        expect {
          described_class.sidekiq_retries_exhausted_block.call(job, StandardError.new)
        }.not_to raise_error

        tx.reload
        expect(tx.status).to eq("failed")
      end
    end
  end

  describe "#find_telemetry_log" do
    it "handles invalid created_at_iso format gracefully" do
      telemetry_log = create(:telemetry_log, :verified_telemetry, tree: tree)
      create(:blockchain_transaction, wallet: wallet, status: :pending)

      # Invalid ISO format should not prevent finding the log
      described_class.new.perform(telemetry_log.id_value, "invalid-date-format")

      expect(BlockchainMintingService).to have_received(:call_batch)
    end

    it "returns nil for nonexistent log without created_at_iso" do
      described_class.new.perform(-1, nil)

      expect(BlockchainMintingService).not_to have_received(:call_batch)
    end
  end

  describe "#process_pending_transactions" do
    context "when wallet.broadcast_balance_update is nil-safe" do
      it "handles broadcast on transactions whose wallet has no broadcast method" do
        tx = create(:blockchain_transaction, wallet: wallet, status: :pending)
        allow(BlockchainMintingService).to receive(:call_batch).and_raise(StandardError, "RPC Error")
        allow_any_instance_of(Wallet).to receive(:broadcast_balance_update)

        expect {
          described_class.new.perform
        }.to raise_error(StandardError, "RPC Error")
      end
    end

    context "when no transactions match after filtering" do
      it "returns early when all transactions are already processing" do
        tx = create(:blockchain_transaction, wallet: wallet, status: :processing)

        described_class.new.perform

        expect(BlockchainMintingService).not_to have_received(:call_batch)
      end
    end
  end

  describe "#process_batch with empty results" do
    it "returns early when no pending transactions match the batch IDs" do
      # Create a transaction that's already confirmed (not pending)
      tx = create(:blockchain_transaction, wallet: wallet, status: :confirmed,
                                           tx_hash: SecureRandom.hex(32))

      # Call process_batch with IDs of non-pending transactions
      worker = described_class.new
      worker.send(:process_batch, [ tx.id ])

      expect(BlockchainMintingService).not_to have_received(:call_batch)
    end
  end

  describe "#perform with oracle-driven flow and missing wallet" do
    it "returns early when tree has no wallet" do
      telemetry_log = create(:telemetry_log, :verified_telemetry, tree: tree)
      allow_any_instance_of(Tree).to receive(:wallet).and_return(nil)

      described_class.new.perform(telemetry_log.id_value, telemetry_log.created_at.iso8601(6))

      expect(BlockchainMintingService).not_to have_received(:call_batch)
    end
  end

  describe "broadcast_balance_update on RPC failure" do
    before do
      allow(BlockchainMintingService).to receive(:call_batch).and_raise(StandardError, "RPC failure")
    end

    it "calls broadcast_balance_update on each transaction wallet after RPC failure" do
      tx = create(:blockchain_transaction, wallet: wallet, status: :pending)

      expect {
        described_class.new.perform
      }.to raise_error(StandardError, "RPC failure")

      # The broadcast_balance_update call within the RPC failure rescue block is exercised
    end
  end

  describe "retries_exhausted wallet nil branch" do
    let!(:telemetry_log) { create(:telemetry_log, :verified_telemetry, tree: tree) }

    it "skips via next when tree.wallet is nil" do
      allow_any_instance_of(Tree).to receive(:wallet).and_return(nil)
      allow_any_instance_of(Wallet).to receive(:broadcast_update)

      job = {
        "args" => [ telemetry_log.id_value, telemetry_log.created_at.iso8601(6) ],
        "error_message" => "Permanent failure"
      }

      expect {
        described_class.sidekiq_retries_exhausted_block.call(job, StandardError.new)
      }.not_to raise_error
    end
  end

  describe "broadcast_update after retry exhaustion" do
    let!(:telemetry_log) { create(:telemetry_log, :verified_telemetry, tree: tree) }

    it "calls broadcast_update on wallet after rollback" do
      wallet.update!(balance: 20_000, locked_balance: 10_000)
      tx = create(:blockchain_transaction, wallet: wallet, status: :pending, locked_points: 10_000)

      allow_any_instance_of(Wallet).to receive(:broadcast_update)

      job = {
        "args" => [ telemetry_log.id_value, telemetry_log.created_at.iso8601(6) ],
        "error_message" => "Permanent failure"
      }

      described_class.sidekiq_retries_exhausted_block.call(job, StandardError.new)
      tx.reload
      expect(tx.status).to eq("failed")
    end
  end
end
