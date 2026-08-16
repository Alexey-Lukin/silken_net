# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Insight generation and daily aggregation flow" do
  let(:organization) { create(:organization) }
  let(:cluster) { create(:cluster, organization: organization) }
  let(:tree_family) { create(:tree_family) }

  before do
    allow_any_instance_of(Tree).to receive(:broadcast_map_update)
    allow_any_instance_of(Wallet).to receive(:broadcast_balance_update)
    allow(AlertNotificationWorker).to receive(:perform_async)
    allow(EmergencyResponseService).to receive(:call)
    allow(ClusterHealthCheckWorker).to receive(:perform_async)
  end

  describe "InsightGeneratorService" do
    let!(:tree1) { create(:tree, cluster: cluster, tree_family: tree_family) }
    let!(:tree2) { create(:tree, cluster: cluster, tree_family: tree_family) }
    let(:yesterday) { Time.current.utc.to_date - 1 }

    before do
      # Create telemetry logs for yesterday
      travel_to yesterday.beginning_of_day + 12.hours do
        create(:telemetry_log, tree: tree1, temperature_c: 25.0,
                               voltage_mv: 3500, z_value: 25.0,
                               acoustic_events: 5, growth_points: 10,
                               bio_status: :homeostasis)
        create(:telemetry_log, tree: tree2, temperature_c: 26.0,
                               voltage_mv: 3600, z_value: 24.0,
                               acoustic_events: 3, growth_points: 15,
                               bio_status: :homeostasis)
      end
    end

    it "generates daily health summaries for each tree" do
      result = InsightGeneratorService.call(yesterday)

      expect(result[:processed_count]).to eq(2)
      expect(AiInsight.where(insight_type: :daily_health_summary, target_date: yesterday).count).to be >= 2

      tree1_insight = AiInsight.find_by(analyzable: tree1, target_date: yesterday)
      expect(tree1_insight).to be_present
      expect(tree1_insight.stress_index).to be_between(0, 1)
      expect(tree1_insight.total_growth_points).to eq(10)
    end

    it "generates cluster-level summary" do
      InsightGeneratorService.call(yesterday)

      cluster_insight = AiInsight.find_by(analyzable: cluster, target_date: yesterday)
      expect(cluster_insight).to be_present
      expect(cluster_insight.total_growth_points).to eq(25) # 10 + 15
    end

    it "is idempotent — re-running clears old insights" do
      InsightGeneratorService.call(yesterday)
      first_count = AiInsight.where(target_date: yesterday).count

      InsightGeneratorService.call(yesterday)
      second_count = AiInsight.where(target_date: yesterday).count

      expect(second_count).to eq(first_count)
    end

    it "does not accuse a tree that deviates hard from the cluster baseline (fraud guard declared inert)" do
      travel_to yesterday.beginning_of_day + 6.hours do
        # Одноосьове екстремальне відхилення температури від базлайну кластера
        create(:telemetry_log, tree: tree1, temperature_c: 80.0,
                               voltage_mv: 3500, z_value: 25.0,
                               acoustic_events: 5, growth_points: 10,
                               bio_status: :homeostasis)
        # Normal tree
        create(:telemetry_log, tree: tree2, temperature_c: 22.0,
                               voltage_mv: 3500, z_value: 25.0,
                               acoustic_events: 5, growth_points: 10,
                               bio_status: :homeostasis)
      end

      InsightGeneratorService.call(yesterday)

      tree1_insight = AiInsight.find_by(analyzable: tree1, target_date: yesterday)
      # Одна вісь відхилення — легітимна біологія; звинувачення вимагає ДРУГОГО
      # виміряного сигналу (`InsightGeneratorService#detect_fraud?` — оголошена
      # інертність), тож грошовий хвіст фроду не смикається.
      expect(tree1_insight).to be_present
      expect(tree1_insight.fraud_detected).to be false
      expect(tree1_insight.total_growth_points).to eq(20) # 10 (before) + 10 — ріст не обнулено
    end

    it "cleans up old telemetry logs older than 7 days" do
      old_log = nil
      travel_to 10.days.ago do
        old_log = create(:telemetry_log, tree: tree1)
      end

      InsightGeneratorService.call(yesterday)

      expect(TelemetryLog.where(id: old_log.id).exists?).to be false
    end
  end

  describe "DailyAggregationWorker orchestration" do
    let!(:tree) { create(:tree, cluster: cluster, tree_family: tree_family) }
    let(:yesterday) { Time.current.utc.to_date - 1 }

    it "triggers InsightGeneratorOrchestratorWorker and chains to ClusterHealthCheckWorker via batch callback" do
      travel_to yesterday.beginning_of_day + 12.hours do
        create(:telemetry_log, tree: tree, temperature_c: 22.0,
                               voltage_mv: 3500, z_value: 25.0,
                               acoustic_events: 5, growth_points: 10)
      end

      DailyAggregationWorker.new.perform(yesterday.to_s)

      # [A-3]: DailyAggregationWorker тепер запускає батч-оркестратор замість синхронного виклику.
      # ClusterHealthCheckWorker запускається з InsightBatchCallbacks#on_success після батчу.
      expect(InsightGeneratorOrchestratorWorker.jobs.size).to eq(1)
      expect(InsightGeneratorOrchestratorWorker.jobs.first["args"]).to eq([ yesterday.to_s ])
    end

    it "creates blackout alert when no data exists on weekday" do
      # Create active NaaS contract so cluster is eligible for blackout alert
      create(:naas_contract, organization: organization, cluster: cluster, status: :active)

      # Pick a weekday in the past
      weekday = Date.new(2026, 3, 2) # Monday
      expect { DailyAggregationWorker.new.perform(weekday.to_s) }
        .to change(EwsAlert, :count).by(1)

      # [SLASH-1 gap-D] :field_audit, НЕ :system_fault — fleet-wide блекаут = force-majeure
      # (05_05 §6), а :system_fault накручував би penalty_factor обома гілками.
      alert = EwsAlert.last
      expect(alert.alert_type).to eq("field_audit")
      I18n.with_locale(:uk) { expect(alert.message).to include("БЛЕКАУТ") }
    end
  end

  describe "NaasContract cluster health check (slashing)" do
    let!(:tree1) { create(:tree, cluster: cluster, tree_family: tree_family) }
    let!(:tree2) { create(:tree, cluster: cluster, tree_family: tree_family) }
    let!(:tree3) { create(:tree, cluster: cluster, tree_family: tree_family) }
    let!(:contract) { create(:naas_contract, organization: organization, cluster: cluster) }

    before do
      allow(BurnCarbonTokensWorker).to receive(:perform_async)
    end

    it "activates slashing when >20% trees have critical stress" do
      yesterday = Time.current.utc.to_date - 1

      # 2 out of 3 trees stressed (66% > 20% threshold)
      create(:ai_insight, analyzable: tree1, insight_type: :daily_health_summary,
                          target_date: yesterday, stress_index: 1.0)
      create(:ai_insight, analyzable: tree2, insight_type: :daily_health_summary,
                          target_date: yesterday, stress_index: 1.0)
      create(:ai_insight, analyzable: tree3, insight_type: :daily_health_summary,
                          target_date: yesterday, stress_index: 0.2)

      # [SLASH-1, ⚖️ 2026-07-30] Кластер мусить бути НЕ МЕНШИМ за поріг виродження
      # (N ≥ 1/f = 5) — інакше вердикт `:insufficient_sample` (Field Audit), і предмет
      # цієї спеки, сам слешинг, не перевіряється взагалі. Тому добираємо до 5 дерев:
      # 2 критичних із 5 = 40% > 20%, тобто те саме твердження, але на валідному семплі.
      # `Prosopite.pause` — це фікстурна підготовка, а не поведінка під тестом:
      # `Tree` має `build_default_wallet`/`ensure_calibration` в `after_create`, тож
      # створення двох дерев поспіль виглядає для детектора як N+1.
      Prosopite.pause
      2.times do
        healthy = create(:tree, cluster: cluster, tree_family: tree_family)
        create(:ai_insight, analyzable: healthy, insight_type: :daily_health_summary,
                            target_date: yesterday, stress_index: 0.1)
      end
      Prosopite.resume

      # Set counter cache to match actual active trees
      Cluster.where(id: cluster.id).update_all(active_trees_count: 5)

      # Reload contract so it picks up fresh cluster state
      contract.reload
      # [SLASH-1] >20% → :degraded (chokepoint adjudicates slash-vs-freeze); breach is async.
      expect(contract.check_cluster_health!(yesterday)).to eq(:degraded)

      expect(contract.reload.status).to eq("active")
      expect(BurnCarbonTokensWorker).to have_received(:perform_async)
    end

    it "does not slash when stress is below threshold" do
      yesterday = Time.current.utc.to_date - 1

      # All trees healthy
      create(:ai_insight, analyzable: tree1, insight_type: :daily_health_summary,
                          target_date: yesterday, stress_index: 0.2)
      create(:ai_insight, analyzable: tree2, insight_type: :daily_health_summary,
                          target_date: yesterday, stress_index: 0.1)
      create(:ai_insight, analyzable: tree3, insight_type: :daily_health_summary,
                          target_date: yesterday, stress_index: 0.3)

      Cluster.where(id: cluster.id).update_all(active_trees_count: 3)

      contract.check_cluster_health!(yesterday)

      expect(contract.reload.status).to eq("active")
    end
  end
end
