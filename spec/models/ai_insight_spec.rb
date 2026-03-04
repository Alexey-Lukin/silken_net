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
end
