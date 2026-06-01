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

  # [VPD weather-confounder gate — 00_01 §6.5/§6.6] Discount-only, inert until
  # calibrated. Guards against FALSE slashing during a humid spell (low VPD →
  # suppressed sap on a healthy tree). Must never raise stress and must ship no
  # guessed kPa threshold into the slashing path until ground-truth calibration.
  describe "#apply_weather_confounder" do
    let(:service) { described_class.new }

    it "is inert when avg_vpd is nil (firmware not yet emitting VPD — HW.32)" do
      allow(service).to receive(:vpd_confounder_calibration).and_return({ low_kpa: 0.5, max_discount: 0.4 })
      expect(service.send(:apply_weather_confounder, 0.9, nil, 0.5)).to eq(0.9)
    end

    it "is inert when calibration is absent (no guessed threshold enters slashing)" do
      allow(service).to receive(:vpd_confounder_calibration).and_return(nil)
      expect(service.send(:apply_weather_confounder, 0.9, 0.2, 0.5)).to eq(0.9)
    end

    context "when calibrated (post ground-truth, 08_02 §4)" do
      before { allow(service).to receive(:vpd_confounder_calibration).and_return({ low_kpa: 0.5, max_discount: 0.4 }) }

      it "discounts stress when air is saturated (low VPD) and sap departs baseline" do
        expect(service.send(:apply_weather_confounder, 0.9, 0.2, 0.5)).to eq(0.54) # 0.9 × (1 − 0.4)
      end

      it "never raises stress (discount-only invariant)" do
        expect(service.send(:apply_weather_confounder, 0.9, 0.1, 0.8)).to be <= 0.9
      end

      it "is inert when VPD is not low (normal/high VPD = no weather excuse)" do
        expect(service.send(:apply_weather_confounder, 0.9, 1.8, 0.5)).to eq(0.9)
      end

      it "is inert when sap is near baseline (nothing weather could account for)" do
        expect(service.send(:apply_weather_confounder, 0.9, 0.2, 0.0)).to eq(0.9)
      end
    end
  end

  describe "#vpd_confounder_calibration" do
    let(:service) { described_class.new }

    it "returns nil by default (gate inert until ground-truth calibration)" do
      expect(service.send(:vpd_confounder_calibration)).to be_nil
    end

    it "returns the calibrated config when both ENV thresholds are set" do
      ENV["VPD_CONFOUNDER_LOW_KPA"] = "0.5"
      ENV["VPD_CONFOUNDER_MAX_DISCOUNT"] = "0.4"
      expect(service.send(:vpd_confounder_calibration)).to eq({ low_kpa: 0.5, max_discount: 0.4 })
    ensure
      ENV.delete("VPD_CONFOUNDER_LOW_KPA")
      ENV.delete("VPD_CONFOUNDER_MAX_DISCOUNT")
    end

    # asymmetric branch: low set but discount missing → guard still fires
    it "returns nil when only low_kpa is set (discount missing/zero)" do
      ENV["VPD_CONFOUNDER_LOW_KPA"] = "0.5"
      ENV.delete("VPD_CONFOUNDER_MAX_DISCOUNT")
      expect(service.send(:vpd_confounder_calibration)).to be_nil
    ensure
      ENV.delete("VPD_CONFOUNDER_LOW_KPA")
      ENV.delete("VPD_CONFOUNDER_MAX_DISCOUNT")
    end

    it "clamps max_discount to 1.0" do
      ENV["VPD_CONFOUNDER_LOW_KPA"] = "0.5"
      ENV["VPD_CONFOUNDER_MAX_DISCOUNT"] = "1.5"
      expect(service.send(:vpd_confounder_calibration)[:max_discount]).to eq(1.0)
    ensure
      ENV.delete("VPD_CONFOUNDER_LOW_KPA")
      ENV.delete("VPD_CONFOUNDER_MAX_DISCOUNT")
    end
  end

  describe "VPD gate end-to-end (inert while uncalibrated)" do
    it "plumbs avg_vpd into reasoning yet leaves stress_index unchanged (gate inert)" do
      create(:telemetry_log, tree: tree,
        temperature_c: 40.0, voltage_mv: 3500, z_value: 3.0, sap_flow: 5.0, vpd: 0.1,
        acoustic_events: 2, growth_points: 5,
        bio_status: :stress, metabolism_s: 1000,
        created_at: date.beginning_of_day + 12.hours)

      described_class.call(date)

      insight = AiInsight.find_by(analyzable: tree, insight_type: :daily_health_summary, target_date: date)
      # stress(1)=0.6 + z>2(+0.2) + temp>35(+0.1) = 0.9; VPD present but gate inert (no calibration)
      expect(insight.stress_index).to eq(0.9)
      expect(insight.reasoning["avg_vpd"]).to eq(0.1)
    end
  end

  # [Sap-flow stress term — closes the 00_01 §6.6 GAP where the heuristic ignored
  # sap.] Low sap (below baseline) is the primary DIRECT drought signal. Inert
  # until calibrated; bounded so it corroborates but never solely triggers slashing.
  describe "#sap_stress_contribution" do
    let(:service) { described_class.new }

    it "is inert (0.0) by default — no guessed weight enters live slashing" do
      expect(service.send(:sap_stress_contribution, -0.9)).to eq(0.0)
    end

    context "when calibrated (post ground-truth, 08_02 §4)" do
      before { allow(service).to receive(:sap_stress_calibration).and_return({ threshold: 0.3, weight: 0.2 }) }

      it "adds the weight when sap is well below baseline (drought signal)" do
        expect(service.send(:sap_stress_contribution, -0.5)).to eq(0.2)
      end

      it "ignores high sap (vigour is never penalised)" do
        expect(service.send(:sap_stress_contribution, 0.5)).to eq(0.0)
      end

      it "ignores sap near baseline (shallower than the −threshold floor)" do
        expect(service.send(:sap_stress_contribution, -0.1)).to eq(0.0)
      end
    end
  end

  describe "#sap_stress_calibration" do
    let(:service) { described_class.new }

    it "returns nil by default (term inert until calibrated)" do
      expect(service.send(:sap_stress_calibration)).to be_nil
    end

    it "returns config when both ENV thresholds are set" do
      ENV["STRESS_SAP_LOW_THRESHOLD"] = "0.3"
      ENV["STRESS_SAP_WEIGHT"] = "0.2"
      expect(service.send(:sap_stress_calibration)).to eq({ threshold: 0.3, weight: 0.2 })
    ensure
      ENV.delete("STRESS_SAP_LOW_THRESHOLD")
      ENV.delete("STRESS_SAP_WEIGHT")
    end

    # asymmetric branch
    it "returns nil when only threshold is set (weight ENV missing)" do
      ENV["STRESS_SAP_LOW_THRESHOLD"] = "0.3"
      ENV.delete("STRESS_SAP_WEIGHT")
      expect(service.send(:sap_stress_calibration)).to be_nil
    ensure
      ENV.delete("STRESS_SAP_LOW_THRESHOLD")
      ENV.delete("STRESS_SAP_WEIGHT")
    end
  end

  describe "sap-flow in the stress heuristic" do
    let(:service) { described_class.new }

    it "leaves the heuristic unchanged by default (sap term inert despite low sap)" do
      # status 1 (0.6) + z>2 (0.2) + temp>35 (0.1) = 0.9; sap inert while uncalibrated
      expect(service.send(:calculate_stress_index_heuristic, 1, 40.0, 0, 3.0, -0.9)).to eq(0.9)
    end

    context "when calibrated" do
      before { allow(service).to receive(:sap_stress_calibration).and_return({ threshold: 0.3, weight: 0.2 }) }

      it "raises stress for a low-sap stressed tree" do
        # status 1 (0.6) + low sap (0.2); z/temp normal = 0.8
        expect(service.send(:calculate_stress_index_heuristic, 1, 25.0, 0, 0.5, -0.5)).to eq(0.8)
      end

      it "sap alone (homeostasis tree) cannot reach the 0.83 slash threshold" do
        # status 0 (0.0) + low sap (0.2) = 0.2 — corroborator, never sole trigger
        result = service.send(:calculate_stress_index_heuristic, 0, 25.0, 0, 0.5, -0.9)
        expect(result).to eq(0.2)
        expect(result).to be < 0.83
      end
    end
  end

  describe "sap stress end-to-end (signed deviation plumbed via generate_for_tree)" do
    let(:high_sap_tree) { create(:tree, cluster: cluster, status: :active) }
    let(:low_sap_tree) { create(:tree, cluster: cluster, status: :active) }

    it "applies the sap term only to the below-baseline tree when calibrated" do
      ENV["STRESS_SAP_LOW_THRESHOLD"] = "0.3"
      ENV["STRESS_SAP_WEIGHT"] = "0.2"
      # baseline sap = avg(100, 40) = 70 → low tree signed dev = (40-70)/70 = -0.43 ≤ -0.3
      create(:telemetry_log, tree: high_sap_tree, temperature_c: 25.0, sap_flow: 100.0,
        voltage_mv: 3500, z_value: 0.5, acoustic_events: 1, growth_points: 10,
        bio_status: :homeostasis, metabolism_s: 1000, created_at: date.beginning_of_day + 12.hours)
      create(:telemetry_log, tree: low_sap_tree, temperature_c: 25.0, sap_flow: 40.0,
        voltage_mv: 3500, z_value: 0.5, acoustic_events: 1, growth_points: 10,
        bio_status: :homeostasis, metabolism_s: 1000, created_at: date.beginning_of_day + 12.hours)

      described_class.call(date)

      high = AiInsight.find_by(analyzable: high_sap_tree, target_date: date)
      low = AiInsight.find_by(analyzable: low_sap_tree, target_date: date)
      expect(high.stress_index).to eq(0.0)  # vigour — no penalty
      expect(low.stress_index).to eq(0.2)   # drought corroborator
    ensure
      ENV.delete("STRESS_SAP_LOW_THRESHOLD")
      ENV.delete("STRESS_SAP_WEIGHT")
    end
  end

  # [Acoustic (cavitation) stress term — closes the acoustic half of the 00_01 §6.6
  # heuristic GAP.] acoustic_events = cavitation count (drought signal); chainsaw is
  # a separate panic path. Inert until calibrated; max()'d with sap (correlated).
  describe "#acoustic_stress_contribution" do
    let(:service) { described_class.new }

    it "is inert (0.0) by default even at high cavitation count" do
      expect(service.send(:acoustic_stress_contribution, 200)).to eq(0.0)
    end

    context "when calibrated (post ground-truth, 08_02 §4)" do
      before { allow(service).to receive(:acoustic_stress_calibration).and_return({ threshold: 50, weight: 0.2 }) }

      it "adds the weight when cavitation is at/above the calibrated count" do
        expect(service.send(:acoustic_stress_contribution, 80)).to eq(0.2)
      end

      it "ignores low cavitation (below the count threshold)" do
        expect(service.send(:acoustic_stress_contribution, 10)).to eq(0.0)
      end

      it "treats nil cavitation as inert" do
        expect(service.send(:acoustic_stress_contribution, nil)).to eq(0.0)
      end
    end
  end

  describe "#acoustic_stress_calibration" do
    let(:service) { described_class.new }

    it "returns nil by default (term inert until calibrated)" do
      expect(service.send(:acoustic_stress_calibration)).to be_nil
    end

    it "returns config when both ENV thresholds are set" do
      ENV["STRESS_ACOUSTIC_THRESHOLD"] = "50"
      ENV["STRESS_ACOUSTIC_WEIGHT"] = "0.2"
      expect(service.send(:acoustic_stress_calibration)).to eq({ threshold: 50, weight: 0.2 })
    ensure
      ENV.delete("STRESS_ACOUSTIC_THRESHOLD")
      ENV.delete("STRESS_ACOUSTIC_WEIGHT")
    end
  end

  describe "correlated drought signals (sap + acoustic) do not stack" do
    let(:service) { described_class.new }

    before do
      allow(service).to receive_messages(
        sap_stress_calibration: { threshold: 0.3, weight: 0.2 },
        acoustic_stress_calibration: { threshold: 50, weight: 0.2 }
      )
    end

    it "takes max(sap, acoustic), not their sum (00_01 SLASH-SAFETY)" do
      # status 1 (0.6) + low sap (0.2) AND high cavitation (0.2) → +max(0.2,0.2)=0.2, NOT 0.4
      expect(service.send(:calculate_stress_index_heuristic, 1, 25.0, 80, 0.5, -0.5)).to eq(0.8)
    end

    it "still corroborates when only the acoustic signal fires" do
      # cavitation only (sap normal): status 1 (0.6) + max(0, 0.2) = 0.8
      expect(service.send(:calculate_stress_index_heuristic, 1, 25.0, 80, 0.5, 0.0)).to eq(0.8)
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

  # GenerateClusterInsightWorker path. Distinct from #perform because batch mode
  # is invoked with pre-computed cluster_ids and re-fetches baselines.
  describe "#process_cluster_batch" do
    let(:service) { described_class.new(date) }

    it "skips clusters whose baseline is missing" do
      empty_cluster = create(:cluster) # no telemetry → no baseline row
      expect {
        service.process_cluster_batch([ empty_cluster.id ])
      }.not_to(change(AiInsight, :count))
    end

    it "skips trees whose stats_map entry is nil and counts only generated trees" do
      tree_with_logs    = create(:tree, cluster: cluster, status: :active)
      tree_without_logs = create(:tree, cluster: cluster, status: :active)

      # Two telemetry rows establish a non-degenerate cluster baseline.
      [ tree_with_logs, tree ].each do |t|
        create(:telemetry_log, tree: t,
          temperature_c: 25.0, voltage_mv: 3500, z_value: 0.5, sap_flow: 100.0,
          acoustic_events: 1, growth_points: 10,
          bio_status: :homeostasis, metabolism_s: 1000,
          created_at: date.beginning_of_day + 12.hours)
      end

      processed = service.process_cluster_batch([ cluster.id ])

      expect(processed).to eq(2)
      expect(AiInsight.where(analyzable: tree_without_logs, target_date: date)).to be_empty
      expect(AiInsight.where(analyzable: tree_with_logs, target_date: date)).to exist
    end

    it "does not count trees whose generate_for_tree returns false (avg_temp nil)" do
      # AVG(temperature_c) is NULL when every row's temperature_c is NULL.
      # That yields stats present but stats.avg_temp == nil → generate_for_tree
      # returns false → @processed_count stays put.
      tree_no_temp = create(:tree, cluster: cluster, status: :active)
      [ tree, tree_no_temp ].each do |t|
        create(:telemetry_log, tree: t,
          temperature_c: nil, voltage_mv: 3500, z_value: 0.5, sap_flow: 100.0,
          acoustic_events: 1, growth_points: 0,
          bio_status: :homeostasis, metabolism_s: 1000,
          created_at: date.beginning_of_day + 12.hours)
      end

      processed = service.process_cluster_batch([ cluster.id ])
      expect(processed).to eq(0)
    end
  end

  # ===========================================================================
  # sap_stress_calibration / acoustic_stress_calibration ENV-applied
  # ===========================================================================
  describe "#sap_stress_calibration — clamp" do
    let(:service) { described_class.new }

    it "clamps weight to 0.99 ceiling when ENV exceeds it" do
      ENV["STRESS_SAP_LOW_THRESHOLD"] = "0.3"
      ENV["STRESS_SAP_WEIGHT"] = "1.5"
      expect(service.send(:sap_stress_calibration)).to eq({ threshold: 0.3, weight: 0.99 })
    ensure
      ENV.delete("STRESS_SAP_LOW_THRESHOLD")
      ENV.delete("STRESS_SAP_WEIGHT")
    end
  end

  describe "#acoustic_stress_calibration — ENV-applied" do
    let(:service) { described_class.new }

    it "returns config when both ENV thresholds are set" do
      ENV["STRESS_ACOUSTIC_THRESHOLD"] = "50"
      ENV["STRESS_ACOUSTIC_WEIGHT"] = "0.2"
      expect(service.send(:acoustic_stress_calibration)).to eq({ threshold: 50, weight: 0.2 })
    ensure
      ENV.delete("STRESS_ACOUSTIC_THRESHOLD")
      ENV.delete("STRESS_ACOUSTIC_WEIGHT")
    end

    it "clamps weight to 0.99 ceiling when ENV exceeds it" do
      ENV["STRESS_ACOUSTIC_THRESHOLD"] = "50"
      ENV["STRESS_ACOUSTIC_WEIGHT"] = "2.0"
      expect(service.send(:acoustic_stress_calibration)[:weight]).to eq(0.99)
    ensure
      ENV.delete("STRESS_ACOUSTIC_THRESHOLD")
      ENV.delete("STRESS_ACOUSTIC_WEIGHT")
    end

    # asymmetric branch
    it "returns nil when only threshold is set (weight ENV missing)" do
      ENV["STRESS_ACOUSTIC_THRESHOLD"] = "50"
      ENV.delete("STRESS_ACOUSTIC_WEIGHT")
      expect(service.send(:acoustic_stress_calibration)).to be_nil
    ensure
      ENV.delete("STRESS_ACOUSTIC_THRESHOLD")
      ENV.delete("STRESS_ACOUSTIC_WEIGHT")
    end
  end
end
