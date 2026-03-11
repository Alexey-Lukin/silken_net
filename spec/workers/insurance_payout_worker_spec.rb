# frozen_string_literal: true

require "rails_helper"

RSpec.describe InsurancePayoutWorker, type: :worker do
  let(:organization) { create(:organization, crypto_public_address: "0x" + "ab" * 20) }
  let(:cluster) { create(:cluster, organization: organization) }
  let(:tree) { create(:tree, cluster: cluster, status: :active) }
  let!(:wallet) { create(:wallet, tree: tree) }
  let(:insurance) { create(:parametric_insurance, :triggered, cluster: cluster, organization: organization) }

  before do
    allow(BlockchainMintingService).to receive(:call)
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_prepend_to)
  end

  describe "#perform" do
    it "creates a BlockchainTransaction for payout" do
      expect {
        described_class.new.perform(insurance.id)
      }.to change(BlockchainTransaction, :count).by(1)

      tx = BlockchainTransaction.last
      expect(tx.amount).to eq(insurance.payout_amount)
      expect(tx.to_address).to eq(organization.crypto_public_address)
      expect(tx.status).to eq("pending")
      expect(tx.notes).to include("Страхове відшкодування")
    end

    it "marks insurance as paid" do
      described_class.new.perform(insurance.id)

      insurance.reload
      expect(insurance.status).to eq("paid")
      expect(insurance.paid_at).to be_present
    end

    it "calls BlockchainMintingService to execute payout" do
      described_class.new.perform(insurance.id)

      expect(BlockchainMintingService).to have_received(:call).with(kind_of(Integer))
    end

    it "broadcasts insurance update via Turbo" do
      described_class.new.perform(insurance.id)

      expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).at_least(:once)
      expect(Turbo::StreamsChannel).to have_received(:broadcast_prepend_to)
    end

    it "returns nil for non-existent insurance" do
      expect(described_class.new.perform(-1)).to be_nil
    end

    it "skips non-triggered insurance" do
      active_insurance = create(:parametric_insurance, cluster: cluster, organization: organization, status: :active)

      described_class.new.perform(active_insurance.id)

      expect(BlockchainMintingService).not_to have_received(:call)
    end

    it "skips already paid insurance" do
      insurance.update!(status: :paid, paid_at: Time.current)

      described_class.new.perform(insurance.id)

      expect(BlockchainMintingService).not_to have_received(:call)
    end

    it "returns early when no trees exist in cluster" do
      # Створюємо порожній кластер без дерев
      empty_cluster = create(:cluster, organization: organization)
      empty_insurance = create(:parametric_insurance, :triggered, cluster: empty_cluster, organization: organization)

      expect(Rails.logger).to receive(:error).with(/без жодного дерева/)

      described_class.new.perform(empty_insurance.id)
      expect(BlockchainMintingService).not_to have_received(:call)
    end

    it "re-raises errors for Sidekiq retry" do
      allow(BlockchainMintingService).to receive(:call).and_raise(StandardError, "RPC error")

      expect {
        described_class.new.perform(insurance.id)
      }.to raise_error(StandardError, "RPC error")
    end

    context "when insurance status changes between lock and check (pessimistic lock re-check)" do
      it "skips payout when insurance is no longer triggered after lock" do
        # Simulate: insurance.lock! succeeds, but then status changes to :paid
        allow_any_instance_of(ParametricInsurance).to receive(:lock!) do |ins|
          ins.update_columns(status: :paid, paid_at: Time.current)
        end

        expect {
          described_class.new.perform(insurance.id)
        }.not_to change(BlockchainTransaction, :count)

        expect(BlockchainMintingService).not_to have_received(:call)
      end
    end

    context "when ActiveRecord::RecordNotFound is raised" do
      it "rescues RecordNotFound and logs a warning" do
        allow(ParametricInsurance).to receive(:includes).and_return(ParametricInsurance)
        allow(ParametricInsurance).to receive(:find_by).and_return(insurance)
        allow(insurance).to receive(:status_triggered?).and_return(true)
        allow(insurance).to receive(:lock!).and_raise(ActiveRecord::RecordNotFound)

        expect(Rails.logger).to receive(:warn).with(/зник із Матриці/)

        expect {
          described_class.new.perform(insurance.id)
        }.not_to raise_error
      end
    end

    context "when tx is nil (transaction block exits early via next)" do
      it "does not call BlockchainMintingService" do
        allow_any_instance_of(ParametricInsurance).to receive(:lock!) do |ins|
          ins.update_columns(status: :paid)
        end

        described_class.new.perform(insurance.id)

        expect(BlockchainMintingService).not_to have_received(:call)
      end
    end

    context "when no active trees exist but non-active trees have wallets" do
      it "falls back to non-active tree wallet for audit" do
        # Remove the active tree so no active trees exist
        tree.update!(status: :removed)

        expect {
          described_class.new.perform(insurance.id)
        }.to change(BlockchainTransaction, :count).by(1)

        tx = BlockchainTransaction.last
        expect(tx.wallet.tree).to eq(tree)
        expect(tx.notes).to include("Страхове відшкодування")
      end
    end
  end
end
