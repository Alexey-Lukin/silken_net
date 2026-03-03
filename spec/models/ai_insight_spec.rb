# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiInsight, type: :model do
  describe "#status_label" do
    it "returns 'Fraud Detected' when fraud_detected accessor is set" do
      insight = AiInsight.new(
        insight_type: :daily_health_summary,
        target_date: Date.yesterday,
        stress_index: 0.1,
        reasoning: { "fraud_detected" => true }
      )

      expect(insight.status_label).to eq("Fraud Detected")
    end

    it "returns 'Stable' for healthy summary without fraud" do
      insight = AiInsight.new(
        insight_type: :daily_health_summary,
        target_date: Date.yesterday,
        stress_index: 0.1,
        reasoning: {}
      )

      expect(insight.status_label).to eq("Stable")
    end

    it "returns 'Stressed' for high stress summary" do
      insight = AiInsight.new(
        insight_type: :daily_health_summary,
        target_date: Date.yesterday,
        stress_index: 0.5,
        reasoning: {}
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
end
