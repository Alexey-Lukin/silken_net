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
        [ normal_tree1, normal_tree2 ].each do |t|
          create(:telemetry_log, tree: t,
            temperature_c: 25.0, sap_flow: 100.0, voltage_mv: 3500, z_value: 0.5,
            acoustic_events: 2, growth_points: 10,
            bio_status: :homeostasis, metabolism_s: 1000,
            created_at: date.beginning_of_day + 12.hours)
        end

        # Fraudulent tree: both sap (200) and temp (50) deviate >30% from cluster avg
        create(:telemetry_log, tree: fraudulent_tree,
          temperature_c: 50.0, sap_flow: 200.0, voltage_mv: 3500, z_value: 0.5,
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
        expect(fraud_insight.total_growth_points).to be(0)
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

    it "preserves old telemetry logs with oracle_status dispatched" do
      dispatched_log = create(:telemetry_log, tree: tree,
        temperature_c: 25.0, voltage_mv: 3500, z_value: 0.5,
        acoustic_events: 2, growth_points: 10,
        bio_status: :homeostasis, metabolism_s: 1000,
        oracle_status: "dispatched",
        created_at: 8.days.ago)

      create(:telemetry_log, tree: tree,
        temperature_c: 25.0, voltage_mv: 3500, z_value: 0.5,
        acoustic_events: 2, growth_points: 10,
        bio_status: :homeostasis, metabolism_s: 1000,
        created_at: date.beginning_of_day + 12.hours)

      described_class.call(date)

      expect(TelemetryLog.where(id: dispatched_log.id)).to exist
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

    it "skips trees with nil stats (no avg_temp)" do
      # A tree with active status but no telemetry_logs for the target date
      # should be skipped by generate_for_tree because stats&.avg_temp returns nil
      another_tree = create(:tree, cluster: cluster, status: :active)
      # Create a telemetry log on a different date so the tree has data but not for target date
      create(:telemetry_log, tree: another_tree,
        temperature_c: 25.0, voltage_mv: 3500, z_value: 0.5,
        acoustic_events: 2, growth_points: 10,
        bio_status: :homeostasis, metabolism_s: 1000,
        created_at: (date - 5.days).beginning_of_day + 12.hours)

      described_class.call(date)

      expect(AiInsight.find_by(analyzable: another_tree, insight_type: :daily_health_summary, target_date: date)).to be_nil
    end

    it "generates stress summary for status 1" do
      create(:telemetry_log, tree: tree,
        temperature_c: 40.0, voltage_mv: 3500, z_value: 0.5,
        acoustic_events: 2, growth_points: 5,
        bio_status: :stress, metabolism_s: 1000,
        created_at: date.beginning_of_day + 12.hours)

      described_class.call(date)

      insight = AiInsight.find_by(analyzable: tree, insight_type: :daily_health_summary, target_date: date)
      expect(insight.summary).to include("СТРЕС")
    end

    it "generates anomaly summary for status 2" do
      create(:telemetry_log, tree: tree,
        temperature_c: 25.0, voltage_mv: 3500, z_value: 0.5,
        acoustic_events: 2, growth_points: 5,
        bio_status: :anomaly, metabolism_s: 1000,
        created_at: date.beginning_of_day + 12.hours)

      described_class.call(date)

      insight = AiInsight.find_by(analyzable: tree, insight_type: :daily_health_summary, target_date: date)
      expect(insight.summary).to include("АНОМАЛІЯ")
    end

    it "generates critical summary for status 3 (tamper_detected)" do
      create(:telemetry_log, tree: tree,
        temperature_c: 25.0, voltage_mv: 3500, z_value: 0.5,
        acoustic_events: 2, growth_points: 5,
        bio_status: :tamper_detected, metabolism_s: 1000,
        created_at: date.beginning_of_day + 12.hours)

      described_class.call(date)

      insight = AiInsight.find_by(analyzable: tree, insight_type: :daily_health_summary, target_date: date)
      expect(insight.summary).to include("КРИТИЧНО")
    end

    it "handles errors gracefully and returns false for problematic trees" do
      create(:telemetry_log, tree: tree,
        temperature_c: 25.0, voltage_mv: 3500, z_value: 0.5,
        acoustic_events: 2, growth_points: 10,
        bio_status: :homeostasis, metabolism_s: 1000,
        created_at: date.beginning_of_day + 12.hours)

      allow(AiInsight).to receive(:create!).and_call_original
      allow(AiInsight).to receive(:create!).with(hash_including(analyzable: tree)).and_raise(StandardError, "test error")

      expect(Rails.logger).to receive(:error).with(/Insight.*Помилка/)
      described_class.call(date)
    end

    context "when baseline sap is zero" do
      it "returns false (no fraud) when baseline sap is zero" do
        # Single tree so cluster baseline sap == tree's sap == 0
        tree_zero_sap = create(:tree, cluster: cluster, status: :active)
        create(:telemetry_log, tree: tree_zero_sap,
          temperature_c: 25.0, sap_flow: 0.0, voltage_mv: 3500, z_value: 0.5,
          acoustic_events: 2, growth_points: 10,
          bio_status: :homeostasis, metabolism_s: 1000,
          created_at: date.beginning_of_day + 12.hours)

        described_class.call(date)

        insight = AiInsight.find_by(analyzable: tree_zero_sap, insight_type: :daily_health_summary, target_date: date)
        expect(insight).to be_present
        expect(insight.fraud_detected).to be false
      end
    end

    context "with stress_index calculations" do
      it "includes z-value penalty when |avg_z| > 2.0" do
        create(:telemetry_log, tree: tree,
          temperature_c: 25.0, voltage_mv: 3500, z_value: 3.0,
          acoustic_events: 2, growth_points: 10,
          bio_status: :homeostasis, metabolism_s: 1000,
          created_at: date.beginning_of_day + 12.hours)

        described_class.call(date)

        insight = AiInsight.find_by(analyzable: tree, insight_type: :daily_health_summary, target_date: date)
        # homeostasis (0) → base 0.0, z=3.0 (>2.0) → +0.2 penalty
        expect(insight.stress_index).to eq(0.2)
      end

      it "includes temperature penalty for extreme high temps" do
        create(:telemetry_log, tree: tree,
          temperature_c: 40.0, voltage_mv: 3500, z_value: 0.5,
          acoustic_events: 2, growth_points: 10,
          bio_status: :homeostasis, metabolism_s: 1000,
          created_at: date.beginning_of_day + 12.hours)

        described_class.call(date)

        insight = AiInsight.find_by(analyzable: tree, insight_type: :daily_health_summary, target_date: date)
        # homeostasis (0) → base 0.0, z=0.5 (≤2.0) → no z penalty, temp=40 (>35) → +0.1
        expect(insight.stress_index).to eq(0.1)
      end

      it "includes temperature penalty for extreme low temps" do
        create(:telemetry_log, tree: tree,
          temperature_c: -10.0, voltage_mv: 3500, z_value: 0.5,
          acoustic_events: 2, growth_points: 10,
          bio_status: :homeostasis, metabolism_s: 1000,
          created_at: date.beginning_of_day + 12.hours)

        described_class.call(date)

        insight = AiInsight.find_by(analyzable: tree, insight_type: :daily_health_summary, target_date: date)
        # homeostasis (0) → base 0.0, temp=-10 (<-5) → +0.1
        expect(insight.stress_index).to eq(0.1)
      end

      it "returns stress_index 1.0 for anomaly status (max_status >= 2)" do
        create(:telemetry_log, tree: tree,
          temperature_c: 25.0, voltage_mv: 3500, z_value: 0.5,
          acoustic_events: 2, growth_points: 5,
          bio_status: :anomaly, metabolism_s: 1000,
          created_at: date.beginning_of_day + 12.hours)

        described_class.call(date)

        insight = AiInsight.find_by(analyzable: tree, insight_type: :daily_health_summary, target_date: date)
        # anomaly (2) → return 1.0 immediately
        expect(insight.stress_index).to eq(1.0)
      end

      it "applies base stress 0.6 for status 1 with combined penalties" do
        create(:telemetry_log, tree: tree,
          temperature_c: 40.0, voltage_mv: 3500, z_value: 3.0,
          acoustic_events: 2, growth_points: 5,
          bio_status: :stress, metabolism_s: 1000,
          created_at: date.beginning_of_day + 12.hours)

        described_class.call(date)

        insight = AiInsight.find_by(analyzable: tree, insight_type: :daily_health_summary, target_date: date)
        # stress (1) → base 0.6, z=3.0 (>2.0) → +0.2, temp=40 (>35) → +0.1 = 0.9, min(0.9, 0.99)
        expect(insight.stress_index).to eq(0.9)
      end

      it "returns combined maximum of 0.9 for status 1 with all penalties applied" do
        service = described_class.new
        # status=1 (base=0.6) + z>2.0 (+0.2) + temp>35 (+0.1) = 0.9
        result = service.send(:calculate_stress_index, 1, 40.0, 0, 3.0)
        expect(result).to eq(0.9)
      end
    end

    context "with cluster aggregation and fraud" do
      let(:normal_tree) { create(:tree, cluster: cluster, status: :active) }
      let(:fraud_tree) { create(:tree, cluster: cluster, status: :active) }

      it "includes fraud count in summary when fraud is detected" do
        # Normal tree
        create(:telemetry_log, tree: normal_tree,
          temperature_c: 25.0, sap_flow: 100.0, voltage_mv: 3500, z_value: 0.5,
          acoustic_events: 2, growth_points: 10,
          bio_status: :homeostasis, metabolism_s: 1000,
          created_at: date.beginning_of_day + 12.hours)

        # Fraud tree: both sap and temp deviate >30%
        create(:telemetry_log, tree: fraud_tree,
          temperature_c: 50.0, sap_flow: 200.0, voltage_mv: 3500, z_value: 0.5,
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
        expect(cluster_insight.summary).to include("фрод")
      end
    end
  end

  describe "nil stats branch" do
    it "returns false when stats.avg_temp is nil" do
      service = described_class.new
      stats = double("stats", avg_temp: nil)
      result = service.send(:generate_for_tree, tree, { sap: 1.0, temp: 25.0, z: 0.5 }, stats)
      expect(result).to be false
    end
  end

  describe "ML model integration" do
    context "when model file is missing" do
      it "falls back to heuristic stress_index calculation" do
        create(:telemetry_log, tree: tree,
          temperature_c: 25.0, voltage_mv: 3500, z_value: 0.5,
          acoustic_events: 2, growth_points: 10,
          bio_status: :homeostasis, metabolism_s: 1000,
          created_at: date.beginning_of_day + 12.hours)

        described_class.call(date)

        insight = AiInsight.find_by(analyzable: tree, insight_type: :daily_health_summary, target_date: date)
        # Heuristic: homeostasis (0) → base 0.0, z=0.5 (≤2.0) → no penalty, temp=25 (normal) → 0.0
        expect(insight.stress_index).to be_zero
      end
    end

    context "when model file is present" do
      let(:mock_model) { instance_double(Rumale::Ensemble::RandomForestClassifier) }
      let(:model_data) { Marshal.dump(mock_model) }

      before do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(InsightGeneratorService::MODEL_PATH).and_return(true)
        allow(File).to receive(:exist?).with(InsightGeneratorService::MODEL_DIGEST_PATH).and_return(true)
        allow(File).to receive(:binread).with(InsightGeneratorService::MODEL_PATH).and_return(model_data)
        allow(File).to receive(:read).and_call_original
        allow(File).to receive(:read).with(InsightGeneratorService::MODEL_DIGEST_PATH).and_return(OpenSSL::Digest::SHA256.hexdigest(model_data))
        allow(Marshal).to receive(:load).and_return(mock_model)

        proba_result = Numo::DFloat.cast([ [ 0.3, 0.7 ] ])
        classes = Numo::Int32.cast([ 0, 1 ])
        allow(mock_model).to receive_messages(predict_proba: proba_result, classes: classes)
      end

      it "uses ML model predict_proba for stress_index" do
        create(:telemetry_log, tree: tree,
          temperature_c: 25.0, voltage_mv: 3500, z_value: 0.5,
          acoustic_events: 2, growth_points: 10,
          bio_status: :homeostasis, metabolism_s: 1000,
          created_at: date.beginning_of_day + 12.hours)

        described_class.call(date)

        insight = AiInsight.find_by(analyzable: tree, insight_type: :daily_health_summary, target_date: date)
        expect(insight.stress_index).to eq(0.7)
      end
    end

    context "when model classes are in reversed order [1, 0]" do
      let(:mock_model) { instance_double(Rumale::Ensemble::RandomForestClassifier) }
      let(:model_data) { Marshal.dump(mock_model) }

      before do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(InsightGeneratorService::MODEL_PATH).and_return(true)
        allow(File).to receive(:exist?).with(InsightGeneratorService::MODEL_DIGEST_PATH).and_return(true)
        allow(File).to receive(:binread).with(InsightGeneratorService::MODEL_PATH).and_return(model_data)
        allow(File).to receive(:read).and_call_original
        allow(File).to receive(:read).with(InsightGeneratorService::MODEL_DIGEST_PATH).and_return(OpenSSL::Digest::SHA256.hexdigest(model_data))
        allow(Marshal).to receive(:load).and_return(mock_model)

        # Reversed class order: stress (1) is at index 0
        proba_result = Numo::DFloat.cast([ [ 0.85, 0.15 ] ])
        classes = Numo::Int32.cast([ 1, 0 ])
        allow(mock_model).to receive_messages(predict_proba: proba_result, classes: classes)
      end

      it "correctly indexes the stress class probability" do
        create(:telemetry_log, tree: tree,
          temperature_c: 25.0, voltage_mv: 3500, z_value: 0.5,
          acoustic_events: 2, growth_points: 10,
          bio_status: :homeostasis, metabolism_s: 1000,
          created_at: date.beginning_of_day + 12.hours)

        described_class.call(date)

        insight = AiInsight.find_by(analyzable: tree, insight_type: :daily_health_summary, target_date: date)
        # Class 1 is at index 0 → proba[0, 0] = 0.85
        expect(insight.stress_index).to eq(0.85)
      end
    end

    context "when model lacks stress class (1)" do
      let(:mock_model) { instance_double(Rumale::Ensemble::RandomForestClassifier) }
      let(:model_data) { Marshal.dump(mock_model) }

      before do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(InsightGeneratorService::MODEL_PATH).and_return(true)
        allow(File).to receive(:exist?).with(InsightGeneratorService::MODEL_DIGEST_PATH).and_return(true)
        allow(File).to receive(:binread).with(InsightGeneratorService::MODEL_PATH).and_return(model_data)
        allow(File).to receive(:read).and_call_original
        allow(File).to receive(:read).with(InsightGeneratorService::MODEL_DIGEST_PATH).and_return(OpenSSL::Digest::SHA256.hexdigest(model_data))
        allow(Marshal).to receive(:load).and_return(mock_model)

        proba_result = Numo::DFloat.cast([ [ 1.0 ] ])
        classes = Numo::Int32.cast([ 0 ])
        allow(mock_model).to receive_messages(predict_proba: proba_result, classes: classes)
      end

      it "falls back to heuristic and logs error" do
        expect(Rails.logger).to receive(:error).with(/ML-модель не містить клас 1/)

        create(:telemetry_log, tree: tree,
          temperature_c: 25.0, voltage_mv: 3500, z_value: 3.0,
          acoustic_events: 2, growth_points: 10,
          bio_status: :homeostasis, metabolism_s: 1000,
          created_at: date.beginning_of_day + 12.hours)

        described_class.call(date)

        insight = AiInsight.find_by(analyzable: tree, insight_type: :daily_health_summary, target_date: date)
        # Heuristic fallback: homeostasis + z=3.0 penalty = 0.2
        expect(insight.stress_index).to eq(0.2)
      end
    end

    context "when model loading raises an error" do
      before do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(InsightGeneratorService::MODEL_PATH).and_return(true)
        allow(File).to receive(:binread).with(InsightGeneratorService::MODEL_PATH).and_raise(StandardError, "corrupt model")
      end

      it "falls back to heuristic and logs warning" do
        expect(Rails.logger).to receive(:warn).with(/Не вдалося завантажити ML-модель/)

        create(:telemetry_log, tree: tree,
          temperature_c: 25.0, voltage_mv: 3500, z_value: 3.0,
          acoustic_events: 2, growth_points: 10,
          bio_status: :homeostasis, metabolism_s: 1000,
          created_at: date.beginning_of_day + 12.hours)

        described_class.call(date)

        insight = AiInsight.find_by(analyzable: tree, insight_type: :daily_health_summary, target_date: date)
        # Heuristic fallback: homeostasis + z=3.0 penalty = 0.2
        expect(insight.stress_index).to eq(0.2)
      end
    end

    context "when model digest does not match (tampered file)" do
      before do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(InsightGeneratorService::MODEL_PATH).and_return(true)
        allow(File).to receive(:exist?).with(InsightGeneratorService::MODEL_DIGEST_PATH).and_return(true)
        allow(File).to receive(:binread).with(InsightGeneratorService::MODEL_PATH).and_return("tampered data")
        allow(File).to receive(:read).and_call_original
        allow(File).to receive(:read).with(InsightGeneratorService::MODEL_DIGEST_PATH).and_return("0000000000000000000000000000000000000000000000000000000000000000")
      end

      it "falls back to heuristic and logs warning about integrity" do
        expect(Rails.logger).to receive(:warn).with(/Не вдалося завантажити ML-модель/)

        create(:telemetry_log, tree: tree,
          temperature_c: 25.0, voltage_mv: 3500, z_value: 3.0,
          acoustic_events: 2, growth_points: 10,
          bio_status: :homeostasis, metabolism_s: 1000,
          created_at: date.beginning_of_day + 12.hours)

        described_class.call(date)

        insight = AiInsight.find_by(analyzable: tree, insight_type: :daily_health_summary, target_date: date)
        # Heuristic fallback: homeostasis + z=3.0 penalty = 0.2
        expect(insight.stress_index).to eq(0.2)
      end
    end

    context "when model digest file is missing" do
      before do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(InsightGeneratorService::MODEL_PATH).and_return(true)
        allow(File).to receive(:exist?).with(InsightGeneratorService::MODEL_DIGEST_PATH).and_return(false)
        allow(File).to receive(:binread).with(InsightGeneratorService::MODEL_PATH).and_return("some data")
      end

      it "falls back to heuristic and logs warning about missing digest" do
        expect(Rails.logger).to receive(:warn).with(/Не вдалося завантажити ML-модель/)

        create(:telemetry_log, tree: tree,
          temperature_c: 25.0, voltage_mv: 3500, z_value: 0.5,
          acoustic_events: 2, growth_points: 10,
          bio_status: :homeostasis, metabolism_s: 1000,
          created_at: date.beginning_of_day + 12.hours)

        described_class.call(date)

        insight = AiInsight.find_by(analyzable: tree, insight_type: :daily_health_summary, target_date: date)
        expect(insight.stress_index).to be_zero
      end
    end
  end

  describe "fraud detection bypasses ML model" do
    let(:normal_tree1) { create(:tree, cluster: cluster, status: :active) }
    let(:fraudulent_tree) { create(:tree, cluster: cluster, status: :active) }

    it "assigns stress_index 1.0 for fraud without querying AI model" do
      # Normal tree establishes baseline
      create(:telemetry_log, tree: normal_tree1,
        temperature_c: 25.0, sap_flow: 100.0, voltage_mv: 3500, z_value: 0.5,
        acoustic_events: 2, growth_points: 10,
        bio_status: :homeostasis, metabolism_s: 1000,
        created_at: date.beginning_of_day + 12.hours)

      # Fraudulent tree: both sap (200) and temp (50) deviate >30% from cluster avg
      create(:telemetry_log, tree: fraudulent_tree,
        temperature_c: 50.0, sap_flow: 200.0, voltage_mv: 3500, z_value: 0.5,
        acoustic_events: 2, growth_points: 10,
        bio_status: :homeostasis, metabolism_s: 1000,
        created_at: date.beginning_of_day + 12.hours)

      described_class.call(date)

      fraud_insight = AiInsight.find_by(
        analyzable: fraudulent_tree,
        insight_type: :daily_health_summary,
        target_date: date
      )
      expect(fraud_insight.stress_index).to eq(1.0)
      expect(fraud_insight.fraud_detected).to be true
    end
  end

  describe ".cleanup_old_logs!" do
    it "deletes telemetry logs older than 7 days when called as class method" do
      old_log = create(:telemetry_log, tree: tree,
        temperature_c: 25.0, voltage_mv: 3500, z_value: 0.5,
        acoustic_events: 2, growth_points: 10,
        bio_status: :homeostasis, metabolism_s: 1000,
        created_at: 8.days.ago)

      described_class.cleanup_old_logs!

      expect(TelemetryLog.where(id: old_log.id)).not_to exist
    end

    it "preserves dispatched logs when called as class method" do
      dispatched_log = create(:telemetry_log, tree: tree,
        temperature_c: 25.0, voltage_mv: 3500, z_value: 0.5,
        acoustic_events: 2, growth_points: 10,
        bio_status: :homeostasis, metabolism_s: 1000,
        oracle_status: "dispatched",
        created_at: 8.days.ago)

      described_class.cleanup_old_logs!

      expect(TelemetryLog.where(id: dispatched_log.id)).to exist
    end

    it "preserves recent logs (less than 7 days old)" do
      recent_log = create(:telemetry_log, tree: tree,
        temperature_c: 25.0, voltage_mv: 3500, z_value: 0.5,
        acoustic_events: 2, growth_points: 10,
        bio_status: :homeostasis, metabolism_s: 1000,
        created_at: 3.days.ago)

      described_class.cleanup_old_logs!

      expect(TelemetryLog.where(id: recent_log.id)).to exist
    end
  end
end
