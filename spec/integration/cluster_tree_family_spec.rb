# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Cluster health and tree family management" do
  let(:organization) { create(:organization) }
  let(:cluster) { create(:cluster, organization: organization, timezone: "Europe/Kyiv") }
  let(:tree_family) { create(:tree_family, :common_oak) }

  before do
    silence_broadcasts!(:tree_map, :wallet_balance)
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

  # [ARCH.100] Доти тут стояв describe «Cluster local_yesterday respects timezone» — два
  # приклади, що пінили пер-кластерну добу. Вони перевіряли ЗОНУ, але жодного разу не
  # звели її з добою, якою інсайт реально записано, тож промах був для них невидимий.
  # ⚠️ Час заморожено на моменті нічного крона (02:00 UTC): саме там дві дати розходяться.
  describe "Reporting-date anchor holds across timezones" do
    it "finds the cluster's own insight even when its timezone is west of UTC-2" do
      travel_to(Time.utc(2026, 8, 13, 2, 0, 0)) do
        expect(Time.use_zone("America/Manaus") { Date.yesterday }).not_to eq(AiInsight.reporting_date)

        cluster.update!(environmental_settings: { "timezone" => "America/Manaus" })
        create(:ai_insight, analyzable: cluster, insight_type: :daily_health_summary,
                            target_date: AiInsight.reporting_date, stress_index: 0.4)

        expect(cluster.recalculate_health_index!).to eq(0.6)
      end
    end

    it "gives an eastern cluster the same answer on the same data" do
      travel_to(Time.utc(2026, 8, 13, 2, 0, 0)) do
        cluster.update!(environmental_settings: { "timezone" => "Asia/Jakarta" })
        create(:ai_insight, analyzable: cluster, insight_type: :daily_health_summary,
                            target_date: AiInsight.reporting_date, stress_index: 0.4)

        expect(cluster.recalculate_health_index!).to eq(0.6)
      end
    end
  end

  describe "Cluster health_index management" do
    # [ARCH.84] Доти: «defaults to 1.0 when no data».
    it "reports «not measured» rather than inventing a reading" do
      expect(cluster.health_index).to be_nil
    end

    it "recalculates based on AI insight" do
      yesterday = AiInsight.reporting_date
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
    # [SEC.11] Post-cutover the attractor takes (x₀, y₀, z₀) directly.
    # These tests exercise that surface with deterministic inputs.
    it "computes deterministic z values for identical (x₀, y₀, z₀)" do
      z1 = SilkenNet::Attractor.calculate_z_from_state(0.1, 0.2, 0.3, 25.0, 5).first
      z2 = SilkenNet::Attractor.calculate_z_from_state(0.1, 0.2, 0.3, 25.0, 5).first
      expect(z1).to eq(z2)
    end

    it "returns different values for different inputs" do
      z1 = SilkenNet::Attractor.calculate_z_from_state(0.1, 0.2, 0.3, 25.0, 5).first
      z2 = SilkenNet::Attractor.calculate_z_from_state(-0.4, 0.5, -0.1, 50.0, 80).first
      expect(z1).not_to eq(z2)
    end

    it "checks homeostasis correctly" do
      family = create(:tree_family) # z_min: 5.0, z_max: 45.0
      # [E.64] homeostatic? now takes temp (ρ-relative ceiling); temp=0 → ρ=28 → ceiling=45
      expect(SilkenNet::Attractor.homeostatic?(25.0, family, 0.0)).to be true
      expect(SilkenNet::Attractor.homeostatic?(1.0, family, 0.0)).to be false
      expect(SilkenNet::Attractor.homeostatic?(50.0, family, 0.0)).to be false
    end

    it "generates trajectory as flat array" do
      trajectory = SilkenNet::Attractor.generate_trajectory(0.1, 0.2, 0.3, 25.0, 5)
      expect(trajectory.length).to eq(SilkenNet::Attractor::ITERATIONS * 3)
      expect(trajectory).to all(be_a(Float))
    end
  end
end
