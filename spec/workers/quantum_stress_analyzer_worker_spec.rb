# frozen_string_literal: true

require "rails_helper"

RSpec.describe QuantumStressAnalyzerWorker, type: :worker do
  let(:organization) { create(:organization) }
  let(:cluster) { create(:cluster, organization: organization) }
  let(:tree_family) { create(:tree_family) }

  before do
    # Stub Prometheus metric to avoid registry issues in tests
    allow(SilkenNet::Metrics::CLUSTER_ENTROPY_SCORE).to receive(:set)
  end

  describe "#perform" do
    context "with nonexistent cluster" do
      it "returns nil without error" do
        expect { described_class.new.perform(-1) }.not_to raise_error
      end
    end

    context "with insufficient telemetry data" do
      it "does not update cluster entropy_score" do
        tree = create(:tree, cluster: cluster, tree_family: tree_family)
        create_list(:telemetry_log, 10, tree: tree)

        described_class.new.perform(cluster.id)

        expect(cluster.reload.entropy_score).to be_nil
      end

      it "does not create an EwsAlert" do
        expect { described_class.new.perform(cluster.id) }.not_to change(EwsAlert, :count)
      end
    end

    context "with sufficient healthy telemetry (high entropy)" do
      before do
        tree = create(:tree, cluster: cluster, tree_family: tree_family)
        # Create 50 logs with diverse z_values (healthy forest)
        50.times do |i|
          create(:telemetry_log, tree: tree, z_value: 5.0 + (i * 0.8), created_at: 1.hour.ago)
        end
      end

      it "updates cluster entropy_score" do
        described_class.new.perform(cluster.id)

        expect(cluster.reload.entropy_score).to be_a(Float)
        expect(cluster.entropy_score).to be > 0.0
      end

      it "sets Prometheus metric" do
        described_class.new.perform(cluster.id)

        expect(SilkenNet::Metrics::CLUSTER_ENTROPY_SCORE).to have_received(:set).with(
          anything,
          labels: { cluster_id: cluster.id.to_s }
        )
      end

      it "does not create EwsAlert for high entropy" do
        expect { described_class.new.perform(cluster.id) }.not_to change(EwsAlert, :count)
      end
    end

    context "with stressed telemetry (low entropy)" do
      before do
        tree = create(:tree, cluster: cluster, tree_family: tree_family)
        # Create 50 logs with nearly identical z_values (stressed forest)
        50.times do
          create(:telemetry_log, tree: tree, z_value: 29.0 + rand(-0.01..0.01), created_at: 1.hour.ago)
        end
      end

      it "creates a quantum_pre_stress EwsAlert" do
        expect { described_class.new.perform(cluster.id) }.to change(EwsAlert, :count).by(1)

        alert = EwsAlert.last
        expect(alert.alert_type).to eq("quantum_pre_stress")
        expect(alert.severity).to eq("medium")
        expect(alert.cluster_id).to eq(cluster.id)
        expect(alert.message).to include("ПЕРЕДСТРЕСОВИЙ СИГНАЛ")
        expect(alert.message).to include(cluster.name)
      end

      it "updates cluster with low entropy_score" do
        described_class.new.perform(cluster.id)

        score = cluster.reload.entropy_score
        expect(score).to be < described_class::CRITICAL_ENTROPY_THRESHOLD
      end

      it "does not create duplicate alert within silence period" do
        described_class.new.perform(cluster.id)

        expect { described_class.new.perform(cluster.id) }.not_to change(EwsAlert, :count)
      end

      it "invalidates oracle yield cache" do
        Rails.cache.write("oracle_expected_yield_24h", 42)

        described_class.new.perform(cluster.id)

        expect(Rails.cache.read("oracle_expected_yield_24h")).to be_nil
      end
    end

    context "ignores old telemetry outside analysis window" do
      before do
        tree = create(:tree, cluster: cluster, tree_family: tree_family)
        # Create 50 logs outside the 24-hour window
        50.times do
          create(:telemetry_log, tree: tree, z_value: 29.0, created_at: 48.hours.ago)
        end
      end

      it "treats as insufficient data" do
        described_class.new.perform(cluster.id)

        expect(cluster.reload.entropy_score).to be_nil
      end
    end

    context "skips records with nil z_value" do
      before do
        tree = create(:tree, cluster: cluster, tree_family: tree_family)
        # Create 50 logs without z_value
        50.times do
          create(:telemetry_log, tree: tree, z_value: nil, created_at: 1.hour.ago)
        end
      end

      it "treats as insufficient data" do
        described_class.new.perform(cluster.id)

        expect(cluster.reload.entropy_score).to be_nil
      end
    end
  end

  describe "Sidekiq configuration" do
    it "uses the alerts queue" do
      expect(described_class.get_sidekiq_options["queue"]).to eq("alerts")
    end

    it "retries 3 times" do
      expect(described_class.get_sidekiq_options["retry"]).to eq(3)
    end
  end

  describe "constants" do
    it "has CRITICAL_ENTROPY_THRESHOLD of 0.65" do
      expect(described_class::CRITICAL_ENTROPY_THRESHOLD).to eq(0.65)
    end

    it "has ANALYSIS_WINDOW of 24 hours" do
      expect(described_class::ANALYSIS_WINDOW).to eq(24.hours)
    end

    it "has SILENCE_PERIOD of 1 hour" do
      expect(described_class::SILENCE_PERIOD).to eq(1.hour)
    end
  end
end
