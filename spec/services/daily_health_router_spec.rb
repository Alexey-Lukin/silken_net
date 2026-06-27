# frozen_string_literal: true

require "rails_helper"

RSpec.describe DailyHealthRouter do
  let(:org)         { create(:organization) }
  let(:cluster)     { create(:cluster, organization: org) }
  let(:target_date) { Date.yesterday }
  let(:router)      { described_class.new(cluster, target_date) }

  # active_trees_count — денормалізований лічильник (оновлюється Tree-колбеками);
  # у тестах виставляємо прямо, як в insurance_payout_flow_spec.
  def set_active_count(count)
    Cluster.where(id: cluster.id).update_all(active_trees_count: count)
    cluster.reload
  end

  describe "#skipped?" do
    it "is true when the cluster has no active trees" do
      set_active_count(0)
      expect(router.skipped?).to be true
    end

    it "is false when active trees exist" do
      create(:tree, cluster: cluster, status: :active)
      set_active_count(1)
      expect(router.skipped?).to be false
    end
  end

  describe "#blackout?" do
    it "is true when active trees exist but no insights — the tree fell silent (force-majeure)" do
      create(:tree, cluster: cluster, status: :active)
      set_active_count(1)
      expect(router.blackout?).to be true
    end

    it "is false when insights exist for the date" do
      tree = create(:tree, cluster: cluster, status: :active)
      create(:ai_insight, analyzable: tree, target_date: target_date, stress_index: 0.1)
      set_active_count(1)
      expect(router.blackout?).to be false
    end

    it "is false when there are no active trees (skipped, not blackout)" do
      set_active_count(0)
      expect(router.blackout?).to be false
    end
  end

  describe "#critical_count" do
    it "counts insights at or above the given threshold" do
      trees = create_list(:tree, 3, cluster: cluster, status: :active)
      create(:ai_insight, analyzable: trees[0], target_date: target_date, stress_index: 0.9)
      create(:ai_insight, analyzable: trees[1], target_date: target_date, stress_index: 0.83)
      create(:ai_insight, analyzable: trees[2], target_date: target_date, stress_index: 0.5)
      set_active_count(3)

      expect(router.critical_count(0.83)).to eq(2)
      expect(router.critical_count(0.8)).to eq(2)
      expect(router.critical_count(0.95)).to eq(0)
    end
  end

  describe "#insights" do
    it "scopes to daily_health_summary for active trees on the target date only" do
      tree = create(:tree, cluster: cluster, status: :active)
      create(:ai_insight, analyzable: tree, target_date: target_date, stress_index: 0.4)
      # інший день — поза зрізом
      create(:ai_insight, analyzable: tree, target_date: target_date - 1, stress_index: 0.9)
      set_active_count(1)

      expect(router.insights.count).to eq(1)
    end
  end
end
