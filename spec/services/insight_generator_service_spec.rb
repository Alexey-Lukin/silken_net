# frozen_string_literal: true

require "rails_helper"

RSpec.describe InsightGeneratorService, type: :service do
  let(:date) { Time.current.utc.to_date - 1 }
  let(:cluster) { create(:cluster) }
  let(:tree) { create(:tree, cluster: cluster, status: :active) }

  before do
    allow_any_instance_of(Wallet).to receive(:broadcast_balance_update)
    allow_any_instance_of(Tree).to receive(:broadcast_map_update)

    # create_fraud_alert! викликається в InsightGeneratorService, але визначений як приватний
    # class method у AlertDispatchService. Використовуємо without_partial_double_verification.
    without_partial_double_verification {
      allow(AlertDispatchService).to receive(:create_fraud_alert!)
    }
  end

  describe "#perform" do
    it "creates daily health summary insights for each tree" do
      create(:telemetry_log, tree: tree,
        temperature_c: 25.0, voltage_mv: 3500, z_value: 0.5,
        acoustic_events: 2, growth_points: 10,
        bio_status: :homeostasis, metabolism_s: 1000,
        created_at: date.beginning_of_day + 12.hours)

      described_class.call(date)

      insight = AiInsight.find_by(analyzable: tree, insight_type: :daily_health_summary, target_date: date)
      expect(insight).to be_present
      expect(insight.average_temperature).to eq(25.0)
      expect(insight.total_growth_points).to eq(10)
      expect(insight.fraud_detected).to be false
      expect(insight.summary).to include("ГОМЕОСТАЗ")
    end

    context "when sap and temp both deviate >30% from cluster baseline" do
      let(:normal_tree1) { create(:tree, cluster: cluster, status: :active) }
      let(:normal_tree2) { create(:tree, cluster: cluster, status: :active) }
      let(:fraudulent_tree) { create(:tree, cluster: cluster, status: :active) }

      before do
        # Two normal trees establish the baseline centre
        [normal_tree1, normal_tree2].each do |t|
          create(:telemetry_log, tree: t,
            temperature_c: 25.0, voltage_mv: 3500, z_value: 0.5,
            acoustic_events: 2, growth_points: 10,
            bio_status: :homeostasis, metabolism_s: 1000,
            created_at: date.beginning_of_day + 12.hours)
        end

        # Fraudulent tree: both sap (200) and temp (50) deviate >30% from cluster avg
        create(:telemetry_log, tree: fraudulent_tree,
          temperature_c: 50.0, voltage_mv: 3500, z_value: 0.5,
          acoustic_events: 2, growth_points: 10,
          bio_status: :homeostasis, metabolism_s: 1000,
          created_at: date.beginning_of_day + 12.hours)
      end

      it "detects fraud when sap and temp both deviate >30% from cluster baseline" do
        described_class.call(date)

        fraud_insight = AiInsight.find_by(
          analyzable: fraudulent_tree,
          insight_type: :daily_health_summary,
          target_date: date
        )
        expect(fraud_insight).to be_present
        expect(fraud_insight.fraud_detected).to be true
      end

      it "assigns zero growth points to fraudulent trees" do
        described_class.call(date)

        fraud_insight = AiInsight.find_by(
          analyzable: fraudulent_tree,
          insight_type: :daily_health_summary,
          target_date: date
        )
        expect(fraud_insight.total_growth_points).to eq(0)
      end
    end

    it "calculates correct stress_index for healthy trees (status 0)" do
      create(:telemetry_log, tree: tree,
        temperature_c: 25.0, voltage_mv: 3500, z_value: 0.5,
        acoustic_events: 2, growth_points: 10,
        bio_status: :homeostasis, metabolism_s: 1000,
        created_at: date.beginning_of_day + 12.hours)

      described_class.call(date)

      insight = AiInsight.find_by(analyzable: tree, insight_type: :daily_health_summary, target_date: date)
      # homeostasis (0) → base 0.0, z=0.5 (≤2.0) → no penalty, temp=25 (normal) → no penalty
      expect(insight.stress_index).to be_zero
    end

    it "is idempotent - reruns delete and recreate insights" do
      create(:telemetry_log, tree: tree,
        temperature_c: 25.0, voltage_mv: 3500, z_value: 0.5,
        acoustic_events: 2, growth_points: 10,
        bio_status: :homeostasis, metabolism_s: 1000,
        created_at: date.beginning_of_day + 12.hours)

      described_class.call(date)
      initial_count = AiInsight.where(insight_type: :daily_health_summary, target_date: date).count
      expect(initial_count).to be > 0

      described_class.call(date)
      final_count = AiInsight.where(insight_type: :daily_health_summary, target_date: date).count

      expect(final_count).to eq(initial_count)
    end

    it "creates cluster-level aggregation insights" do
      create(:telemetry_log, tree: tree,
        temperature_c: 25.0, voltage_mv: 3500, z_value: 0.5,
        acoustic_events: 2, growth_points: 10,
        bio_status: :homeostasis, metabolism_s: 1000,
        created_at: date.beginning_of_day + 12.hours)

      described_class.call(date)

      cluster_insight = AiInsight.find_by(
        analyzable: cluster,
        insight_type: :daily_health_summary,
        target_date: date
      )
      expect(cluster_insight).to be_present
      expect(cluster_insight.summary).to include(cluster.name)
    end

    it "cleans up telemetry logs older than 7 days" do
      old_log = create(:telemetry_log, tree: tree,
        temperature_c: 25.0, voltage_mv: 3500, z_value: 0.5,
        acoustic_events: 2, growth_points: 10,
        bio_status: :homeostasis, metabolism_s: 1000,
        created_at: 8.days.ago)

      create(:telemetry_log, tree: tree,
        temperature_c: 25.0, voltage_mv: 3500, z_value: 0.5,
        acoustic_events: 2, growth_points: 10,
        bio_status: :homeostasis, metabolism_s: 1000,
        created_at: date.beginning_of_day + 12.hours)

      described_class.call(date)

      expect(TelemetryLog.where(id: old_log.id)).not_to exist
    end

    it "returns processed count and date" do
      create(:telemetry_log, tree: tree,
        temperature_c: 25.0, voltage_mv: 3500, z_value: 0.5,
        acoustic_events: 2, growth_points: 10,
        bio_status: :homeostasis, metabolism_s: 1000,
        created_at: date.beginning_of_day + 12.hours)

      result = described_class.call(date)

      expect(result).to eq({ processed_count: 1, date: date })
    end

    it "skips trees without telemetry logs" do
      tree_with_logs = create(:tree, cluster: cluster, status: :active)
      tree_without_logs = create(:tree, cluster: cluster, status: :active)

      create(:telemetry_log, tree: tree_with_logs,
        temperature_c: 25.0, voltage_mv: 3500, z_value: 0.5,
        acoustic_events: 2, growth_points: 10,
        bio_status: :homeostasis, metabolism_s: 1000,
        created_at: date.beginning_of_day + 12.hours)

      described_class.call(date)

      expect(AiInsight.find_by(analyzable: tree_without_logs, insight_type: :daily_health_summary)).to be_nil
      expect(AiInsight.find_by(analyzable: tree_with_logs, insight_type: :daily_health_summary)).to be_present
    end
  end
end
