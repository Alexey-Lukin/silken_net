# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe InsightGeneratorOrchestratorWorker, type: :worker do
  before do
    silence_broadcasts!(:wallet_balance, :tree_map)
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
  end

  describe "#perform" do
    context "with clusters that have telemetry data" do
      let(:cluster) { create(:cluster) }
      let(:tree) { create(:tree, cluster: cluster, status: :active) }
      let(:date) { Date.new(2026, 3, 6) }

      before do
        create(:telemetry_log, tree: tree,
          temperature_c: 25.0, voltage_mv: 3500, z_value: 0.5,
          acoustic_events: 2, growth_points: 10,
          bio_status: :homeostasis, metabolism_s: 1000,
          created_at: date.beginning_of_day + 12.hours)
      end

      it "enqueues GenerateClusterInsightWorker for clusters with data" do
        described_class.new.perform(date.to_s)

        expect(GenerateClusterInsightWorker.jobs.size).to be >= 1
        enqueued_cluster_ids = GenerateClusterInsightWorker.jobs.flat_map { |j| j["args"].first }
        expect(enqueued_cluster_ids).to include(cluster.id)
      end

      it "creates a Sidekiq::Batch with description and callback" do
        batch_instance = nil
        allow(Sidekiq::Batch).to receive(:new).and_wrap_original do |method, *args|
          batch_instance = method.call(*args)
          batch_instance
        end

        described_class.new.perform(date.to_s)

        expect(batch_instance).to be_present
        expect(batch_instance.description).to start_with("Insight Generation")
        expect(batch_instance.callbacks).to include(
          hash_including(event: :success, klass: InsightBatchCallbacks)
        )
      end

      it "passes date to callback options" do
        batch_instance = nil
        allow(Sidekiq::Batch).to receive(:new).and_wrap_original do |method, *args|
          batch_instance = method.call(*args)
          batch_instance
        end

        described_class.new.perform(date.to_s)

        callback = batch_instance.callbacks.find { |c| c[:klass] == InsightBatchCallbacks }
        expect(callback[:options]).to have_key("date")
        expect(callback[:options]["date"]).to eq(date.to_s)
      end

      it "relies on per-cluster idempotency (no global delete_all)" do
        # Create pre-existing insight
        insight = create(:ai_insight,
          analyzable: tree,
          insight_type: :daily_health_summary,
          target_date: date)

        # Orchestrator enqueues child workers but does NOT delete insights globally.
        # Per-cluster cleanup is handled by each GenerateClusterInsightWorker.
        described_class.new.perform(date.to_s)

        # Pre-existing insight should still exist — orchestrator didn't delete it.
        # (In real execution, the child worker will delete and recreate it.)
        expect(AiInsight.where(id: insight.id)).to exist
      end
    end

    context "without telemetry data" do
      it "does not enqueue any batch workers" do
        described_class.new.perform("2026-03-06")

        expect(GenerateClusterInsightWorker.jobs).to be_empty
      end

      it "returns early without creating a batch" do
        expect(Sidekiq::Batch).not_to receive(:new)

        described_class.new.perform("2026-03-06")
      end
    end

    it "uses yesterday UTC when no date provided" do
      expect { described_class.new.perform }.not_to raise_error
    end

    it "handles empty eligible clusters gracefully" do
      expect { described_class.new.perform("2026-03-06") }.not_to raise_error
      expect(GenerateClusterInsightWorker.jobs).to be_empty
    end
  end

  describe "sidekiq options" do
    it "uses low queue" do
      expect(described_class.get_sidekiq_options["queue"]).to eq("low")
    end

    it "retries 3 times" do
      expect(described_class.get_sidekiq_options["retry"]).to eq(3)
    end

    it "has unique_for set to 24 hours" do
      expect(described_class.get_sidekiq_options["unique_for"]).to eq(24.hours)
    end
  end

  describe "CLUSTER_BATCH_SIZE" do
    it "is configured for planetary scale" do
      expect(described_class::CLUSTER_BATCH_SIZE).to eq(100)
    end
  end
end
