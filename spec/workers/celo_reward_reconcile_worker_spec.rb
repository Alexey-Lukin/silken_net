# frozen_string_literal: true

require "rails_helper"

RSpec.describe CeloRewardReconcileWorker, type: :worker do
  let(:cluster) { create(:cluster) }

  def celo_reward_intent(status:, created_at:, network: "celo", token: :cusd)
    BlockchainTransaction.create!(
      cluster: cluster,
      sourceable: cluster,
      to_address: "0x1234567890abcdef1234567890abcdef12345678",
      amount: "5.0",
      token_type: token,
      blockchain_network: network,
      reward_date: Date.current,
      status: status,
      tx_hash: (status == :sent ? "0x#{SecureRandom.hex(32)}" : nil),
      notes: "test celo reward intent"
    ).tap { |tx| tx.update_column(:created_at, created_at) }
  end

  describe "#perform" do
    it "escalates a stale :pending Celo reward intent to :manual_review" do
      stuck = celo_reward_intent(status: :pending, created_at: 1.hour.ago)

      described_class.new.perform

      expect(stuck.reload.status_manual_review?).to be true
      expect(stuck.error_message).to include("ARCH.64")
    end

    it "leaves a fresh :pending intent alone (still inside the live retry window)" do
      fresh = celo_reward_intent(status: :pending, created_at: 5.minutes.ago)

      described_class.new.perform

      expect(fresh.reload.status_pending?).to be true
    end

    it "ignores :sent intents — those already armed CeloConfirmationWorker" do
      sent = celo_reward_intent(status: :sent, created_at: 1.hour.ago)

      described_class.new.perform

      expect(sent.reload.status_sent?).to be true
    end

    # Filter independence — split so a regression dropping EITHER `.where` is caught.
    it "ignores non-cusd tokens even on the celo network (token_type filter)" do
      carbon = celo_reward_intent(status: :pending, created_at: 1.hour.ago, token: :carbon_coin)

      described_class.new.perform

      expect(carbon.reload.status_pending?).to be true
    end

    it "ignores cusd on a non-celo network (blockchain_network filter)" do
      evm = celo_reward_intent(status: :pending, created_at: 1.hour.ago, network: "evm")

      described_class.new.perform

      expect(evm.reload.status_pending?).to be true
    end

    it "is a no-op (no escalation, no warn) when nothing is stuck" do
      celo_reward_intent(status: :pending, created_at: 5.minutes.ago) # fresh only
      allow(Rails.logger).to receive(:warn)

      described_class.new.perform

      expect(Rails.logger).not_to have_received(:warn)
    end

    it "caps escalations at BATCH_LIMIT per run (backlog drains across crons)" do
      stub_const("#{described_class}::BATCH_LIMIT", 2)
      3.times { |i| celo_reward_intent(status: :pending, created_at: (1.hour + i.minutes).ago) }

      described_class.new.perform

      expect(BlockchainTransaction.status_manual_review.count).to eq(2)
    end

    it "skips :pending older than LOOKBACK (forensic tail, deliberately out of sweep scope)" do
      ancient = celo_reward_intent(status: :pending, created_at: 8.days.ago)

      described_class.new.perform

      expect(ancient.reload.status_pending?).to be true
    end

    it "reload-guard: skips a row a live poller settled between SELECT and reload" do
      stuck = celo_reward_intent(status: :pending, created_at: 1.hour.ago)
      # Simulate CeloConfirmationWorker completing it after our SELECT — reload sees non-:pending.
      allow(BlockchainTransaction).to receive(:find_with_partition_pruning)
        .and_return(instance_double(BlockchainTransaction, status_pending?: false))

      described_class.new.perform

      expect(stuck.reload.status_pending?).to be true # untouched, not escalated
    end

    # ARCH.64 MONEY-SAFETY LINCHPIN: after escalation, dedup MUST still block a re-pay.
    # If a refactor drops :manual_review from reward_already_sent?, this fails BEFORE a
    # silent double-pay of cUSD ships (Opus review M2).
    it "escalated :manual_review still blocks a same-day re-pay (no double-pay)" do
      celo_reward_intent(status: :pending, created_at: 1.hour.ago)

      described_class.new.perform

      service = Celo::CommunityRewardService.new(cluster, Date.current)
      expect(service.send(:reward_already_sent?)).to be true
    end
  end
end
