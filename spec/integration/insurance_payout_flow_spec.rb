# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Parametric insurance payout flow" do
  let(:organization) { create(:organization) }
  let(:cluster) { create(:cluster, organization: organization) }
  let(:tree_family) { create(:tree_family) }

  before do
    allow_any_instance_of(Tree).to receive(:broadcast_map_update)
    allow_any_instance_of(Wallet).to receive(:broadcast_balance_update)
    allow(AlertNotificationWorker).to receive(:perform_async)
    allow(BlockchainMintingService).to receive(:call)
  end

  describe "ParametricInsurance daily evaluation" do
    let!(:tree1) { create(:tree, cluster: cluster, tree_family: tree_family) }
    let!(:tree2) { create(:tree, cluster: cluster, tree_family: tree_family) }
    let!(:insurance) do
      create(:parametric_insurance, organization: organization, cluster: cluster,
                                    payout_amount: 100_000, threshold_value: 30,
                                    required_confirmations: 1)
    end

    before do
      Cluster.where(id: cluster.id).update_all(active_trees_count: 2)
      allow(InsurancePayoutWorker).to receive(:perform_async)
    end

    it "triggers payout when damage exceeds threshold" do
      yesterday = Time.current.utc.to_date - 1

      # Both trees critically stressed (100% > 30% threshold)
      create(:ai_insight, analyzable: tree1, insight_type: :daily_health_summary,
                          target_date: yesterday, stress_index: 0.9)
      create(:ai_insight, analyzable: tree2, insight_type: :daily_health_summary,
                          target_date: yesterday, stress_index: 0.95)

      insurance.evaluate_daily_health!(yesterday)

      expect(insurance.reload.status).to eq("triggered")
      expect(InsurancePayoutWorker).to have_received(:perform_async).with(insurance.id)
    end

    it "does not trigger when damage is below threshold" do
      yesterday = Time.current.utc.to_date - 1

      # Only 1 of 2 trees stressed (50% > 30% would trigger, but stress < 0.8 doesn't qualify)
      create(:ai_insight, analyzable: tree1, insight_type: :daily_health_summary,
                          target_date: yesterday, stress_index: 0.5)
      create(:ai_insight, analyzable: tree2, insight_type: :daily_health_summary,
                          target_date: yesterday, stress_index: 0.3)

      insurance.evaluate_daily_health!(yesterday)

      expect(insurance.reload.status).to eq("active")
      expect(InsurancePayoutWorker).not_to have_received(:perform_async)
    end

    it "skips evaluation if insurance is not active" do
      insurance.update_column(:status, ParametricInsurance.statuses[:expired])

      yesterday = Time.current.utc.to_date - 1
      create(:ai_insight, analyzable: tree1, insight_type: :daily_health_summary,
                          target_date: yesterday, stress_index: 1.0)

      insurance.evaluate_daily_health!(yesterday)
      expect(insurance.reload.status).to eq("expired")
    end
  end

  describe "InsurancePayoutWorker execution" do
    let!(:tree) { create(:tree, cluster: cluster, tree_family: tree_family) }
    let!(:insurance) do
      create(:parametric_insurance, organization: organization, cluster: cluster,
                                    payout_amount: 50_000, threshold_value: 30,
                                    status: :triggered)
    end

    it "creates blockchain transaction and marks insurance as paid" do
      InsurancePayoutWorker.new.perform(insurance.id)

      insurance.reload
      expect(insurance.status).to eq("paid")
      expect(insurance.paid_at).to be_present

      tx = insurance.blockchain_transaction
      expect(tx).to be_present
      expect(tx.amount).to eq(50_000)
      expect(tx.status).to eq("pending")
      expect(tx.to_address).to eq(organization.crypto_public_address)
      expect(BlockchainMintingService).to have_received(:call).with(tx.id)
    end

    it "skips if insurance is not in triggered state" do
      insurance.update_column(:status, ParametricInsurance.statuses[:active])

      InsurancePayoutWorker.new.perform(insurance.id)

      expect(insurance.reload.status).to eq("active")
      expect(BlockchainMintingService).not_to have_received(:call)
    end

    it "handles missing insurance record gracefully" do
      expect { InsurancePayoutWorker.new.perform(999_999) }.not_to raise_error
    end
  end

  describe "ClusterHealthCheckWorker orchestration" do
    let!(:tree) { create(:tree, cluster: cluster, tree_family: tree_family) }
    let!(:contract) { create(:naas_contract, organization: organization, cluster: cluster) }

    before do
      allow(BurnCarbonTokensWorker).to receive(:perform_async)
    end

    it "recalculates cluster health index" do
      yesterday = Time.current.utc.to_date - 1
      create(:ai_insight, analyzable: cluster, insight_type: :daily_health_summary,
                          target_date: yesterday, stress_index: 0.3)

      ClusterHealthCheckWorker.new.perform(yesterday.to_s)

      cluster.reload
      expect(cluster.health_index).to eq(0.7) # 1.0 - 0.3
    end

    it "checks all active NaaS contracts" do
      Cluster.where(id: cluster.id).update_all(active_trees_count: 1)
      yesterday = Time.current.utc.to_date - 1
      create(:ai_insight, analyzable: tree, insight_type: :daily_health_summary,
                          target_date: yesterday, stress_index: 1.0)

      ClusterHealthCheckWorker.new.perform(yesterday.to_s)

      # 100% critical > 20% threshold → breach
      expect(contract.reload.status).to eq("breached")
    end
  end
end
