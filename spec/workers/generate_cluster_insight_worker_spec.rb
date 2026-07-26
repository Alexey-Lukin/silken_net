# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe GenerateClusterInsightWorker, type: :worker do
  let(:cluster) { create(:cluster) }
  let(:tree) { create(:tree, cluster: cluster, status: :active) }
  let(:date) { Date.new(2026, 3, 6) }

  before do
    allow_any_instance_of(Wallet).to receive(:broadcast_balance_update)
    allow_any_instance_of(Tree).to receive(:broadcast_map_update)
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)

    without_partial_double_verification {
      allow(AlertDispatchService).to receive(:create_fraud_alert!)
    }
  end

  describe "#perform" do
    context "with clusters that have telemetry data" do
      before do
        create(:telemetry_log, tree: tree,
          temperature_c: 25.0, voltage_mv: 3500, z_value: 0.5,
          acoustic_events: 2, growth_points: 10, sap_flow: 100.0,
          bio_status: :homeostasis, metabolism_s: 1000,
          created_at: date.beginning_of_day + 12.hours)
      end

      it "creates tree-level AiInsight for each tree with data" do
        expect {
          described_class.new.perform([ cluster.id ], date.to_s)
        }.to change { AiInsight.where(analyzable_type: "Tree", insight_type: :daily_health_summary).count }.by(1)

        insight = AiInsight.find_by(analyzable: tree, insight_type: :daily_health_summary, target_date: date)
        expect(insight).to be_present
        expect(insight.average_temperature).to eq(25.0)
      end

      it "creates cluster-level AiInsight aggregation" do
        expect {
          described_class.new.perform([ cluster.id ], date.to_s)
        }.to change { AiInsight.where(analyzable_type: "Cluster", insight_type: :daily_health_summary).count }.by(1)

        cluster_insight = AiInsight.find_by(
          analyzable: cluster,
          insight_type: :daily_health_summary,
          target_date: date
        )
        expect(cluster_insight).to be_present
        expect(cluster_insight.summary).to include(cluster.name)
      end

      it "is idempotent — reruns delete and recreate insights" do
        described_class.new.perform([ cluster.id ], date.to_s)
        initial_count = AiInsight.where(insight_type: :daily_health_summary, target_date: date).count
        expect(initial_count).to be > 0

        described_class.new.perform([ cluster.id ], date.to_s)
        final_count = AiInsight.where(insight_type: :daily_health_summary, target_date: date).count

        expect(final_count).to eq(initial_count)
      end
    end

    context "with clusters that have no telemetry data" do
      it "handles gracefully" do
        expect {
          described_class.new.perform([ cluster.id ], date.to_s)
        }.not_to raise_error
      end

      it "does not create insights" do
        expect {
          described_class.new.perform([ cluster.id ], date.to_s)
        }.not_to change(AiInsight, :count)
      end
    end

    context "with empty cluster_ids" do
      it "handles gracefully" do
        expect {
          described_class.new.perform([], date.to_s)
        }.not_to raise_error
      end
    end

    context "with nonexistent cluster_ids" do
      it "handles gracefully" do
        expect {
          described_class.new.perform([ -1, -2 ], date.to_s)
        }.not_to raise_error
      end
    end

    context "with multiple clusters" do
      let(:cluster2) { create(:cluster) }
      let(:tree2) { create(:tree, cluster: cluster2, status: :active) }

      before do
        create(:telemetry_log, tree: tree,
          temperature_c: 25.0, voltage_mv: 3500, z_value: 0.5,
          acoustic_events: 2, growth_points: 10, sap_flow: 100.0,
          bio_status: :homeostasis, metabolism_s: 1000,
          created_at: date.beginning_of_day + 12.hours)
        create(:telemetry_log, tree: tree2,
          temperature_c: 30.0, voltage_mv: 4000, z_value: 0.8,
          acoustic_events: 5, growth_points: 20, sap_flow: 120.0,
          bio_status: :homeostasis, metabolism_s: 1200,
          created_at: date.beginning_of_day + 12.hours)
      end

      it "processes multiple clusters in a single chunk" do
        expect {
          described_class.new.perform([ cluster.id, cluster2.id ], date.to_s)
        }.to change { AiInsight.where(analyzable_type: "Tree", insight_type: :daily_health_summary).count }.by(2)
      end
    end

    context "with fraud detection in batch mode" do
      let(:normal_tree) { create(:tree, cluster: cluster, status: :active) }
      let(:fraudulent_tree) { create(:tree, cluster: cluster, status: :active) }

      before do
        # Два нормальних дерева встановлюють базлайн кластера
        [ tree, normal_tree ].each do |t|
          create(:telemetry_log, tree: t,
            temperature_c: 25.0, voltage_mv: 3500, z_value: 0.5,
            acoustic_events: 2, growth_points: 10, sap_flow: 100.0,
            bio_status: :homeostasis, metabolism_s: 1000,
            created_at: date.beginning_of_day + 12.hours)
        end

        # Фрод-дерево: і sap_flow, і temperature відхиляються >30% від базлайну
        create(:telemetry_log, tree: fraudulent_tree,
          temperature_c: 50.0, voltage_mv: 3500, z_value: 0.5,
          acoustic_events: 2, growth_points: 10, sap_flow: 200.0,
          bio_status: :homeostasis, metabolism_s: 1000,
          created_at: date.beginning_of_day + 12.hours)
      end

      it "marks fraudulent tree insight with fraud_detected=true" do
        described_class.new.perform([ cluster.id ], date.to_s)

        fraud_insight = AiInsight.find_by(
          analyzable: fraudulent_tree,
          insight_type: :daily_health_summary,
          target_date: date
        )
        expect(fraud_insight).to be_present
        expect(fraud_insight.fraud_detected).to be true
        expect(fraud_insight.stress_index).to eq(1.0)
        expect(fraud_insight.total_growth_points).to eq(0)
      end

      it "creates cluster summary mentioning fraud count" do
        described_class.new.perform([ cluster.id ], date.to_s)

        cluster_insight = AiInsight.find_by(
          analyzable: cluster,
          insight_type: :daily_health_summary,
          target_date: date
        )
        expect(cluster_insight).to be_present
        expect(cluster_insight.summary).to include("фрод")
      end
    end
  end

  describe "sidekiq options" do
    it "uses low queue" do
      expect(described_class.get_sidekiq_options["queue"]).to eq("low")
    end

    it "retries 3 times" do
      expect(described_class.get_sidekiq_options["retry"]).to eq(3)
    end
  end

  describe "error handling" do
    context "when process_cluster_batch raises an error" do
      before do
        allow_any_instance_of(InsightGeneratorService).to receive(:process_cluster_batch)
          .and_raise(StandardError, "DB timeout")
      end

      it "logs the error and re-raises for Sidekiq retry" do
        expect(Rails.logger).to receive(:error).with(/Помилка чанку/)

        expect {
          described_class.new.perform([ cluster.id ], date.to_s)
        }.to raise_error(StandardError, "DB timeout")
      end
    end
  end
end
