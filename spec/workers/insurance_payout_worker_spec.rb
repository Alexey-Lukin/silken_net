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

    context "with satellite verification guard (Cosmic Eye)" do
      before do
        allow_any_instance_of(EwsAlert).to receive(:dispatch_notifications!)
        allow_any_instance_of(EwsAlert).to receive(:broadcast_new_alert)
        allow_any_instance_of(EwsAlert).to receive(:broadcast_alert_update)
        allow_any_instance_of(EwsAlert).to receive(:schedule_satellite_verification!)
      end

      it "skips payout when unverified fire alerts exist in cluster" do
        create(:ews_alert, :fire, cluster: cluster, tree: tree, satellite_status: :unverified)

        described_class.new.perform(insurance.id)

        expect(BlockchainMintingService).not_to have_received(:call)
      end

      it "skips payout when inconclusive fire alerts exist in cluster" do
        create(:ews_alert, :fire, cluster: cluster, tree: tree, satellite_status: :inconclusive)

        described_class.new.perform(insurance.id)

        expect(BlockchainMintingService).not_to have_received(:call)
      end

      it "proceeds with payout when fire alerts are satellite_verified" do
        create(:ews_alert, :fire, cluster: cluster, tree: tree, satellite_status: :verified)

        expect {
          described_class.new.perform(insurance.id)
        }.to change(BlockchainTransaction, :count).by(1)
      end

      it "proceeds with payout when no fire/drought alerts exist" do
        create(:ews_alert, cluster: cluster, tree: tree, alert_type: :vandalism_breach)

        expect {
          described_class.new.perform(insurance.id)
        }.to change(BlockchainTransaction, :count).by(1)
      end

      it "logs satellite pending message for unverified alerts" do
        create(:ews_alert, :fire, cluster: cluster, tree: tree, satellite_status: :unverified)
        expect(Rails.logger).to receive(:info).with(/очікуємо супутникову верифікацію/)

        described_class.new.perform(insurance.id)
      end

      it "logs manual audit message for inconclusive alerts" do
        create(:ews_alert, :fire, cluster: cluster, tree: tree, satellite_status: :inconclusive)
        expect(Rails.logger).to receive(:warn).with(/ручний DAO-аудит/)

        described_class.new.perform(insurance.id)
      end
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
        allow(ParametricInsurance).to receive_messages(includes: ParametricInsurance, find_by: insurance)
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

    context "when insurance uses Etherisc DIP" do
      let(:etherisc_insurance) do
        create(:parametric_insurance, :triggered,
               cluster: cluster, organization: organization,
               etherisc_policy_id: "42")
      end
      let(:fake_tx_hash) { "0x" + "fa" * 32 }

      before do
        claim_service_instance = instance_double(Etherisc::ClaimService, claim!: fake_tx_hash)
        allow(Etherisc::ClaimService).to receive(:new).and_return(claim_service_instance)
        allow(BlockchainConfirmationWorker).to receive(:perform_in)
      end

      it "calls Etherisc::ClaimService instead of BlockchainMintingService" do
        described_class.new.perform(etherisc_insurance.id)

        expect(Etherisc::ClaimService).to have_received(:new).with(etherisc_insurance)
        expect(BlockchainMintingService).not_to have_received(:call)
      end

      it "updates BlockchainTransaction with tx_hash and sent status" do
        described_class.new.perform(etherisc_insurance.id)

        tx = BlockchainTransaction.last
        expect(tx.status).to eq("sent")
        expect(tx.tx_hash).to eq(fake_tx_hash)
      end

      it "enqueues BlockchainConfirmationWorker for receipt polling" do
        described_class.new.perform(etherisc_insurance.id)

        expect(BlockchainConfirmationWorker).to have_received(:perform_in).with(30.seconds, fake_tx_hash)
      end

      it "broadcasts insurance update via Turbo" do
        described_class.new.perform(etherisc_insurance.id)

        expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).at_least(:once)
        expect(Turbo::StreamsChannel).to have_received(:broadcast_prepend_to)
      end
    end
  end
end
