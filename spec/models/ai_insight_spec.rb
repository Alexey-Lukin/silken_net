# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiInsight, type: :model do
  describe "#status_label" do
    it "returns 'Fraud Detected' when fraud_detected is true" do
      insight = AiInsight.new(
        insight_type: :daily_health_summary,
        target_date: Date.yesterday,
        stress_index: 0.1,
        fraud_detected: true
      )

      expect(insight.status_label).to eq("Fraud Detected")
    end

    it "returns 'Stable' for healthy summary without fraud" do
      insight = AiInsight.new(
        insight_type: :daily_health_summary,
        target_date: Date.yesterday,
        stress_index: 0.1,
        fraud_detected: false
      )

      expect(insight.status_label).to eq("Stable")
    end

    it "returns 'Stressed' for high stress summary" do
      insight = AiInsight.new(
        insight_type: :daily_health_summary,
        target_date: Date.yesterday,
        stress_index: 0.5,
        fraud_detected: false
      )

      expect(insight.status_label).to eq("Stressed")
    end

    it "returns 'Forecast' for non-summary types" do
      insight = AiInsight.new(
        insight_type: :drought_probability,
        target_date: Date.tomorrow
      )

      expect(insight.status_label).to eq("Forecast")
    end

    it "returns 'Stable' when stress_index is nil" do
      insight = AiInsight.new(
        insight_type: :daily_health_summary,
        target_date: Date.yesterday,
        stress_index: nil,
        fraud_detected: false
      )

      expect(insight.status_label).to eq("Stable")
    end
  end

  describe "#contract_breach?" do
    it "returns true for daily summary with stress_index >= 0.8" do
      insight = AiInsight.new(
        insight_type: :daily_health_summary,
        target_date: Date.yesterday,
        stress_index: BigDecimal("0.8")
      )

      expect(insight.contract_breach?).to be true
    end

    it "returns false for daily summary with stress_index < 0.8" do
      insight = AiInsight.new(
        insight_type: :daily_health_summary,
        target_date: Date.yesterday,
        stress_index: BigDecimal("0.79")
      )

      expect(insight.contract_breach?).to be false
    end

    it "returns false when stress_index is nil" do
      insight = AiInsight.new(
        insight_type: :daily_health_summary,
        target_date: Date.yesterday,
        stress_index: nil
      )

      expect(insight.contract_breach?).to be false
    end

    it "returns false for non-summary types even with high stress" do
      insight = AiInsight.new(
        insight_type: :drought_probability,
        target_date: Date.tomorrow,
        stress_index: BigDecimal("0.9")
      )

      expect(insight.contract_breach?).to be false
    end

    it "uses decimal precision, not float" do
      # BigDecimal("0.8") == 0.8 exactly, no floating point drift
      insight = AiInsight.new(
        insight_type: :daily_health_summary,
        target_date: Date.yesterday,
        stress_index: BigDecimal("0.8")
      )

      expect(insight.stress_index).to eq(BigDecimal("0.8"))
      expect(insight.contract_breach?).to be true
    end
  end

  describe ".fraudulent" do
    it "returns only insights with fraud_detected true" do
      tree = create(:tree)
      fraud = create(:ai_insight, analyzable: tree, fraud_detected: true, target_date: Date.yesterday)
      create(:ai_insight, analyzable: tree, fraud_detected: false, target_date: 2.days.ago,
             insight_type: :drought_probability)

      expect(AiInsight.fraudulent).to eq([ fraud ])
    end
  end

  # =========================================================================
  # EVIDENCE PERSISTENCE (source_log_ids)
  # =========================================================================
  describe "evidence persistence" do
    let(:tree) { create(:tree) }
    let(:telemetry_logs) { create_list(:telemetry_log, 3, tree: tree) }
    # Партиціоновані таблиці мають composite PK [id, created_at].
    # source_log_ids зберігає лише integer частину.
    let(:log_integer_ids) { telemetry_logs.map { |l| Array(l.id).first } }
    let(:insight) do
      create(:ai_insight,
        analyzable: tree,
        target_date: Date.yesterday,
        source_log_ids: log_integer_ids
      )
    end

    describe "#source_logs" do
      it "returns associated telemetry logs" do
        found_ids = insight.source_logs.map { |l| Array(l.id).first }
        expect(found_ids).to match_array(log_integer_ids)
      end

      it "returns none when source_log_ids is empty" do
        empty_insight = create(:ai_insight, analyzable: tree, target_date: 2.days.ago,
                               insight_type: :drought_probability, source_log_ids: [])
        expect(empty_insight.source_logs).to be_empty
      end
    end

    describe "#attach_evidence!" do
      it "appends new log IDs without duplicates" do
        new_log = create(:telemetry_log, tree: tree)
        new_log_int_id = Array(new_log.id).first
        existing_id = log_integer_ids.first

        insight.attach_evidence!([ new_log_int_id, existing_id ])

        expect(insight.reload.source_log_ids).to include(new_log_int_id)
        expect(insight.source_log_ids.count(existing_id)).to eq(1) # no duplicate
      end
    end

    describe ".referencing_log" do
      it "finds insights that reference a specific telemetry log" do
        results = described_class.referencing_log(log_integer_ids.first)
        expect(results).to include(insight)
      end

      it "does not return insights that do not reference the log" do
        other = create(:ai_insight, analyzable: tree, target_date: 3.days.ago,
                       insight_type: :carbon_yield_forecast, source_log_ids: [])
        results = described_class.referencing_log(log_integer_ids.first)
        expect(results).not_to include(other)
      end
    end
  end
end
