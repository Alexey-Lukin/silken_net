# frozen_string_literal: true

require "rails_helper"

RSpec.describe ParametricInsurance, type: :model do
  before do
    allow(InsurancePayoutWorker).to receive(:perform_async)
    allow_any_instance_of(Tree).to receive(:broadcast_map_update)
  end

  # =========================================================================
  # ENUMS
  # =========================================================================
  describe "enums" do
    it "defines status values with prefix" do
      insurance = build(:parametric_insurance)
      expect(insurance).to respond_to(:status_active?)
      expect(insurance).to respond_to(:status_triggered?)
      expect(insurance).to respond_to(:status_paid?)
      expect(insurance).to respond_to(:status_expired?)
    end

    it "defines trigger_event values without prefix" do
      insurance = build(:parametric_insurance)
      expect(insurance).to respond_to(:critical_fire?)
      expect(insurance).to respond_to(:extreme_drought?)
      expect(insurance).to respond_to(:insect_epidemic?)
    end

    it "defines token_type values with prefix" do
      insurance = build(:parametric_insurance)
      expect(insurance).to respond_to(:token_type_carbon_coin?)
      expect(insurance).to respond_to(:token_type_forest_coin?)
    end
  end

  # =========================================================================
  # VALIDATIONS
  # =========================================================================
  describe "validations" do
    it "is valid with factory defaults" do
      expect(build(:parametric_insurance)).to be_valid
    end

    it "requires payout_amount" do
      expect(build(:parametric_insurance, payout_amount: nil)).not_to be_valid
    end

    it "requires threshold_value" do
      expect(build(:parametric_insurance, threshold_value: nil)).not_to be_valid
    end

    it "rejects threshold_value of 0" do
      ins = build(:parametric_insurance, threshold_value: 0)
      expect(ins).not_to be_valid
      expect(ins.errors[:threshold_value]).to be_present
    end

    it "accepts threshold_value of 100" do
      expect(build(:parametric_insurance, threshold_value: 100)).to be_valid
    end

    it "rejects threshold_value greater than 100" do
      ins = build(:parametric_insurance, threshold_value: 101)
      expect(ins).not_to be_valid
      expect(ins.errors[:threshold_value]).to be_present
    end

    it "accepts threshold_value in valid range (1-100)" do
      expect(build(:parametric_insurance, threshold_value: 30)).to be_valid
      expect(build(:parametric_insurance, threshold_value: 1)).to be_valid
    end
  end

  # =========================================================================
  # ASSOCIATIONS
  # =========================================================================
  describe "associations" do
    it "belongs to organization" do
      assoc = described_class.reflect_on_association(:organization)
      expect(assoc.macro).to eq(:belongs_to)
    end

    it "belongs to cluster" do
      assoc = described_class.reflect_on_association(:cluster)
      expect(assoc.macro).to eq(:belongs_to)
    end

    it "has one blockchain_transaction (polymorphic as sourceable)" do
      assoc = described_class.reflect_on_association(:blockchain_transaction)
      expect(assoc.macro).to eq(:has_one)
    end
  end

  # =========================================================================
  # #recipient_wallet_address
  # =========================================================================
  describe "#recipient_wallet_address" do
    it "returns the cluster organization's crypto_public_address" do
      org     = create(:organization, crypto_public_address: "0xABCD1234" + "0" * 32)
      cluster = create(:cluster, organization: org)
      ins     = create(:parametric_insurance, cluster: cluster, organization: org)

      expect(ins.recipient_wallet_address).to eq(org.crypto_public_address)
    end
  end

  # =========================================================================
  # #evaluate_daily_health!
  # =========================================================================
  describe "#evaluate_daily_health!" do
    let(:org)         { create(:organization) }
    let(:cluster)     { create(:cluster, organization: org) }
    let(:insurance)   { create(:parametric_insurance, organization: org, cluster: cluster, threshold_value: 30) }
    let(:target_date) { Date.yesterday }

    context "when insurance is not active" do
      it "does nothing" do
        insurance.update_column(:status, ParametricInsurance.statuses[:triggered])

        expect {
          insurance.evaluate_daily_health!(target_date)
        }.not_to change { insurance.reload.status }
      end
    end

    context "when cluster has no trees" do
      it "returns early without triggering" do
        expect {
          insurance.evaluate_daily_health!(target_date)
        }.not_to change { insurance.reload.status }
      end
    end

    context "when anomalous trees are below the threshold" do
      it "does not trigger the insurance" do
        # 2 out of 10 trees anomalous = 20%, threshold is 30%
        trees = create_list(:tree, 10, cluster: cluster, status: :active)
        trees[0..1].each { |t| create(:ai_insight, analyzable: t, target_date: target_date, stress_index: 0.9) }
        trees[2..9].each { |t| create(:ai_insight, analyzable: t, target_date: target_date, stress_index: 0.1) }

        insurance.evaluate_daily_health!(target_date)

        expect(insurance.reload).to be_status_active
      end
    end

    context "when anomalous trees meet or exceed the threshold" do
      it "changes status to triggered" do
        # 4 out of 10 trees anomalous = 40%, threshold is 30%
        trees = create_list(:tree, 10, cluster: cluster, status: :active)
        trees[0..3].each { |t| create(:ai_insight, analyzable: t, target_date: target_date, stress_index: 0.95) }
        trees[4..9].each { |t| create(:ai_insight, analyzable: t, target_date: target_date, stress_index: 0.1) }

        insurance.evaluate_daily_health!(target_date)

        expect(insurance.reload).to be_status_triggered
      end

      it "enqueues InsurancePayoutWorker" do
        trees = create_list(:tree, 10, cluster: cluster, status: :active)
        trees[0..3].each { |t| create(:ai_insight, analyzable: t, target_date: target_date, stress_index: 0.95) }
        trees[4..9].each { |t| create(:ai_insight, analyzable: t, target_date: target_date, stress_index: 0.1) }

        insurance.evaluate_daily_health!(target_date)

        expect(InsurancePayoutWorker).to have_received(:perform_async).with(insurance.id)
      end
    end

    context "when exactly at the threshold" do
      it "triggers the insurance (>= check)" do
        # 3 out of 10 = 30.0%, threshold is 30
        trees = create_list(:tree, 10, cluster: cluster, status: :active)
        trees[0..2].each { |t| create(:ai_insight, analyzable: t, target_date: target_date, stress_index: 0.9) }
        trees[3..9].each { |t| create(:ai_insight, analyzable: t, target_date: target_date, stress_index: 0.1) }

        insurance.evaluate_daily_health!(target_date)

        expect(insurance.reload).to be_status_triggered
      end
    end
  end
end
