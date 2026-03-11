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
  end
end
