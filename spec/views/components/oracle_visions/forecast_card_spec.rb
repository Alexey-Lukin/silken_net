# frozen_string_literal: true

require "rails_helper"

RSpec.describe OracleVisions::ForecastCard do
  def mock_insight(
    insight_type: "drought",
    probability_score: 74,
    target_date: Time.utc(2025, 8, 15, 12, 0, 0),
    summary: "Severe moisture deficit expected in sector.",
    yield_impact: "-0.12%"
  )
    OpenStruct.new(
      insight_type: insight_type,
      probability_score: probability_score,
      target_date: target_date,
      summary: summary,
      prediction_data: { "yield_impact" => yield_impact }
    )
  end

  def render_component(insight:)
    component_class.new(insight: insight).call
  end

  describe "insight_type badge" do
    it "renders the insight_type label" do
      html = render_component(insight: mock_insight(insight_type: "drought"))
      expect(html).to include("drought")
    end

    it "displays the insight_type in uppercase styling" do
      html = render_component(insight: mock_insight(insight_type: "flood_risk"))
      expect(html).to include("flood_risk")
    end
  end

  describe "probability_score display" do
    it "renders the probability score as percentage" do
      html = render_component(insight: mock_insight(probability_score: 40))
      expect(html).to include("40%")
    end

    it "renders score 87 correctly" do
      html = render_component(insight: mock_insight(probability_score: 87))
      expect(html).to include("87%")
    end

    it "uses the confidence bar width matching score" do
      html = render_component(insight: mock_insight(probability_score: 65))
      expect(html).to include("width: 65%")
    end
  end

  describe "summary" do
    it "renders the insight summary" do
      html = render_component(insight: mock_insight(summary: "Severe moisture deficit expected."))
      expect(html).to include("Severe moisture deficit expected.")
    end
  end

  describe "yield_impact display" do
    it "shows negative yield_impact with red color" do
      html = render_component(insight: mock_insight(yield_impact: "-0.04%"))
      expect(html).to include("text-red-500")
      expect(html).to include("-0.04%")
    end

    it "shows positive yield_impact with emerald color" do
      html = render_component(insight: mock_insight(yield_impact: "+0.08%"))
      expect(html).to include("text-emerald-500")
      expect(html).to include("+0.08%")
    end

    it "includes the SCC suffix" do
      html = render_component(insight: mock_insight(yield_impact: "-0.12%"))
      expect(html).to include("SCC")
    end
  end

  describe "target_date formatting" do
    it "renders date in dd.mm.yyyy format" do
      html = render_component(insight: mock_insight(target_date: Time.utc(2025, 3, 7, 9, 30, 0)))
      expect(html).to include("07.03.2025")
    end

    it "renders time in HH:MM UTC format" do
      html = render_component(insight: mock_insight(target_date: Time.utc(2025, 8, 15, 14, 45, 0)))
      expect(html).to include("14:45 UTC")
    end
  end

  describe "action buttons" do
    it "renders the shield deployment button" do
      html = render_component(insight: mock_insight)
      expect(html).to include("Deploy Pre-emptive Shield")
    end

    it "renders the ignore singularity button" do
      html = render_component(insight: mock_insight)
      expect(html).to include("Ignore Singularity")
    end
  end

  describe "confidence color" do
    it "uses green color for normal insights" do
      html = render_component(insight: mock_insight(insight_type: "drought", probability_score: 74))
      expect(html).to include("#10b981")
    end

    it "uses red color for high-confidence emergency insights" do
      html = render_component(insight: mock_insight(insight_type: "emergency", probability_score: 95))
      expect(html).to include("#ef4444")
    end
  end

  describe "missing prediction_data [coverage]" do
    it "falls back to the default yield impact and emerald color" do
      insight = OpenStruct.new(
        insight_type: "drought",
        probability_score: 50,
        target_date: Time.utc(2025, 8, 15, 12, 0, 0),
        summary: "No structured prediction payload.",
        prediction_data: nil
      )
      html = render_component(insight: insight)
      expect(html).to include("-0.04%")           # yield_impact_default (dig → nil)
      expect(html).to include("text-emerald-500") # nil.to_f < 0 == false → emerald
    end
  end
end
