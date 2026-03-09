# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Cluster health and tree family management" do
  let(:organization) { create(:organization) }
  let(:cluster) { create(:cluster, organization: organization, timezone: "Europe/Kyiv") }
  let(:tree_family) { create(:tree_family, :common_oak) }

  before do
    allow_any_instance_of(Tree).to receive(:broadcast_map_update)
    allow_any_instance_of(Wallet).to receive(:broadcast_balance_update)
    allow(AlertNotificationWorker).to receive(:perform_async)
  end

  describe "Cluster active_trees_count counter cache" do
    it "increments on active tree creation" do
      expect(cluster.active_trees_count).to eq(0)
      create(:tree, cluster: cluster, tree_family: tree_family)
      expect(cluster.reload.active_trees_count).to eq(1)
    end

    it "increments for multiple trees" do
      create(:tree, cluster: cluster, tree_family: tree_family)
      create(:tree, cluster: cluster, tree_family: tree_family)
      expect(cluster.reload.active_trees_count).to eq(2)
    end

    it "decrements when tree is destroyed" do
      tree = create(:tree, cluster: cluster, tree_family: tree_family)
      expect(cluster.reload.active_trees_count).to eq(1)

      tree.destroy
      expect(cluster.reload.active_trees_count).to eq(0)
    end

    it "decrements when tree status changes from active" do
      tree = create(:tree, cluster: cluster, tree_family: tree_family)
      expect(cluster.reload.active_trees_count).to eq(1)

      tree.update!(status: :dormant)
      expect(cluster.reload.active_trees_count).to eq(0)
    end

    it "adjusts when tree is moved between clusters" do
      cluster2 = create(:cluster, organization: organization)
      tree = create(:tree, cluster: cluster, tree_family: tree_family)

      expect(cluster.reload.active_trees_count).to eq(1)
      expect(cluster2.reload.active_trees_count).to eq(0)

      tree.update!(cluster: cluster2)

      expect(cluster.reload.active_trees_count).to eq(0)
      expect(cluster2.reload.active_trees_count).to eq(1)
    end
  end

  describe "Cluster local_yesterday respects timezone" do
    it "returns yesterday in cluster timezone" do
      cluster.update!(environmental_settings: { "timezone" => "Europe/Kyiv" })
      yesterday = cluster.local_yesterday
      expect(yesterday).to be_a(Date)

      kyiv_yesterday = Time.use_zone("Europe/Kyiv") { Date.yesterday }
      expect(yesterday).to eq(kyiv_yesterday)
    end

    it "falls back to UTC when timezone not set" do
      cluster.update!(environmental_settings: {})
      utc_yesterday = Time.use_zone("UTC") { Date.yesterday }
      expect(cluster.local_yesterday).to eq(utc_yesterday)
    end
  end

  describe "Cluster health_index management" do
    it "defaults to 1.0 when no data" do
      expect(cluster.health_index).to eq(1.0)
    end

    it "recalculates based on AI insight" do
      yesterday = cluster.local_yesterday
      create(:ai_insight, analyzable: cluster, insight_type: :daily_health_summary,
                          target_date: yesterday, stress_index: 0.4)

      new_value = cluster.recalculate_health_index!(yesterday)
      expect(new_value).to eq(0.6) # 1.0 - 0.4
    end
  end

  describe "Cluster active_threats?" do
    it "returns false when no active critical alerts" do
      expect(cluster.active_threats?).to be false
    end

    it "returns true when critical alerts exist" do
      tree = create(:tree, cluster: cluster, tree_family: tree_family)
      create(:ews_alert, :fire, cluster: cluster, tree: tree, status: :active)
      expect(cluster.active_threats?).to be true
    end

    it "returns false after alert is resolved" do
      tree = create(:tree, cluster: cluster, tree_family: tree_family)
      alert = create(:ews_alert, :fire, cluster: cluster, tree: tree, status: :active)
      allow(EmergencyResponseService).to receive(:call)

      alert.resolve!(notes: "Resolved")
      expect(cluster.active_threats?).to be false
    end
  end

  describe "TreeFamily management" do
    it "calculates attractor thresholds" do
      thresholds = tree_family.attractor_thresholds
      expect(thresholds[:min]).to eq(tree_family.critical_z_min.to_f)
      expect(thresholds[:max]).to eq(tree_family.critical_z_max.to_f)
      expect(thresholds[:baseline]).to eq(tree_family.baseline_impedance.to_f)
    end

    it "caches attractor thresholds" do
      cached = tree_family.attractor_thresholds_cached
      expect(cached).to eq(tree_family.attractor_thresholds)
    end

    it "invalidates cache on threshold change" do
      tree_family.attractor_thresholds_cached # populate cache
      tree_family.update!(critical_z_min: 3.0)

      # After invalidation, cache should return fresh data
      new_cached = tree_family.attractor_thresholds_cached
      expect(new_cached[:min]).to eq(3.0)
    end

    it "calculates death_threshold_impedance" do
      # baseline_impedance for common_oak = 1800
      expect(tree_family.death_threshold_impedance).to eq(1800 * 0.3)
    end

    it "determines stress_level correctly" do
      # baseline = 1800
      expect(tree_family.stress_level(500)).to eq(:dead)      # <= 540 (30%)
      expect(tree_family.stress_level(700)).to eq(:critical)   # <= 1080 (60%)
      expect(tree_family.stress_level(1200)).to eq(:warning)   # <= 1440 (80%)
      expect(tree_family.stress_level(1800)).to eq(:normal)    # > 80%
    end

    it "calculates weighted growth points" do
      # common_oak has carbon_sequestration_coefficient: 1.5
      expect(tree_family.weighted_growth_points(100)).to eq(150.0)
    end

    it "checks healthy z range" do
      # common_oak: z_min=8.0, z_max=40.0
      expect(tree_family.healthy_z?(20.0)).to be true
      expect(tree_family.healthy_z?(5.0)).to be false
      expect(tree_family.healthy_z?(45.0)).to be false
    end

    it "generates display_name with scientific name" do
      expect(tree_family.display_name).to eq("Quercus robur (Common Oak)")
    end

    it "generates display_name without scientific name" do
      family = create(:tree_family, scientific_name: nil)
      expect(family.display_name).to eq(family.name)
    end
  end

  describe "SilkenNet::Attractor calculations" do
    it "computes deterministic z values" do
      z1 = SilkenNet::Attractor.calculate_z(12345, 25.0, 5)
      z2 = SilkenNet::Attractor.calculate_z(12345, 25.0, 5)
      expect(z1).to eq(z2) # Deterministic
    end

    it "returns different values for different inputs" do
      z1 = SilkenNet::Attractor.calculate_z(12345, 25.0, 5)
      z2 = SilkenNet::Attractor.calculate_z(99999, 50.0, 80)
      expect(z1).not_to eq(z2)
    end

    it "checks homeostasis correctly" do
      family = create(:tree_family) # z_min: 5.0, z_max: 45.0
      expect(SilkenNet::Attractor.homeostatic?(25.0, family)).to be true
      expect(SilkenNet::Attractor.homeostatic?(1.0, family)).to be false
      expect(SilkenNet::Attractor.homeostatic?(50.0, family)).to be false
    end

    it "generates trajectory as flat array" do
      trajectory = SilkenNet::Attractor.generate_trajectory(12345, 25.0, 5)
      expect(trajectory.length).to eq(SilkenNet::Attractor::ITERATIONS * 3)
      expect(trajectory).to all(be_a(Float))
    end
  end
end
