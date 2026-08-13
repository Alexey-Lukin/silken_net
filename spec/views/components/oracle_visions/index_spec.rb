# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe OracleVisions::Index do
  # [TEST.12] Реальний незбережений `AiInsight`: `insight_type` мусить належати
  # enum'у (доти тут стояли «drought»/«frost_risk», яких модель не приймає), а
  # `target_date` — колонка `date`, не `Time`.
  def mock_insight(insight_type: "drought_probability", probability_score: 74,
                   target_date: Date.current + 1,
                   summary: "Moisture deficit expected.", yield_impact: "-0.04%")
    AiInsight.new(
      insight_type: insight_type,
      probability_score: probability_score,
      target_date: target_date,
      summary: summary,
      prediction_data: { "yield_impact" => yield_impact }
    )
  end

  def mock_cluster(id:, name:)
    c = OpenStruct.new(id: id, name: name)
    c.define_singleton_method(:model_name) { ActiveModel::Name.new(Cluster) }
    c.define_singleton_method(:to_key) { [ id ] }
    c.define_singleton_method(:to_param) { id.to_s }
    c
  end

  def render_component(visions:, emission_forecast:, clusters:, forecast_measured: nil, forecast_total: nil)
    ApplicationController.renderer.render(
      component_class.new(visions: visions, emission_forecast: emission_forecast, clusters: clusters,
                          forecast_measured: forecast_measured, forecast_total: forecast_total),
      layout: false
    )
  end

  let(:clusters) { [ mock_cluster(id: 1, name: "Carpathian-Alpha") ] }
  let(:visions) { [ mock_insight, mock_insight(insight_type: "biodiversity_trend", probability_score: 88) ] }
  let(:html) { render_component(visions: visions, emission_forecast: "12.45", clusters: clusters) }

  describe "header section" do
    it "renders the Strategic Forecast Matrix heading" do
      expect(html).to include("Strategic Forecast Matrix")
    end

    it "renders AI Confidence display" do
      expect(html).to include("AI Confidence")
    end

    it "shows the static AI confidence value" do
      expect(html).to include("94.2%")
    end
  end

  describe "emission_forecast display" do
    it "renders the emission forecast value" do
      expect(html).to include("12.45")
    end

    it "includes SCC label next to forecast" do
      expect(html).to include("SCC")
    end

    it "shows the Projected 24h Emission label" do
      expect(html).to include("Projected 24h Emission")
    end

    # 🔴 [ARCH.84] Прогноз рахується ЛИШЕ по деревах із виміряним стресом, тож без
    # покриття число мовчки видає себе за твердження про весь ліс — а мовчазний
    # відкид невиміряних і є той «відбір», який місія забороняє (`00_01 §1.1`).
    it "declares the coverage when only part of the fleet was measured" do
      rendered = render_component(visions: visions, emission_forecast: "12.45", clusters: clusters,
                                  forecast_measured: 3, forecast_total: 10)

      expect(rendered).to include(I18n.t("ui.measurement.coverage", measured: 3, total: 10))
    end

    # ⊥ Ліхтар: на ПОВНОМУ покритті рядок мовчить — інакше пін вище був би зелений
    # за будь-якої поведінки, а екран ніс би шум там, де твердження повне.
    it "stays silent when the whole fleet was measured" do
      rendered = render_component(visions: visions, emission_forecast: "12.45", clusters: clusters,
                                  forecast_measured: 10, forecast_total: 10)

      expect(rendered).not_to include(I18n.t("ui.measurement.coverage", measured: 10, total: 10))
    end
  end

  describe "visions delegated to ForecastCard" do
    it "renders insight_type for each vision" do
      expect(html).to include("drought_probability")
      expect(html).to include("biodiversity_trend")
    end

    # [TEST.12] `numeric`-колонка → BigDecimal, тож у проді «74.0%», не «74%».
    it "renders probability scores for each vision" do
      expect(html).to include("74.0%")
      expect(html).to include("88.0%")
    end

    it "renders summaries for each vision" do
      expect(html).to include("Moisture deficit expected.")
    end
  end

  describe "simulation_results container" do
    it "renders the simulation_results div" do
      expect(html).to include('id="simulation_results"')
    end

    it "renders the Active Simulations label" do
      expect(html).to include("Active Simulations")
    end
  end

  describe "empty visions list" do
    it "renders without errors when visions is empty" do
      html = render_component(visions: [], emission_forecast: "0.00", clusters: clusters)
      expect(html).to include("Strategic Forecast Matrix")
    end
  end
end
