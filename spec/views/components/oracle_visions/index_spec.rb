# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe OracleVisions::Index do
  def mock_insight(insight_type: "drought", probability_score: 74,
                   target_date: 1.day.from_now.utc,
                   summary: "Moisture deficit expected.", yield_impact: "-0.04%")
    OpenStruct.new(
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

  def render_component(visions:, emission_forecast:, clusters:)
    ApplicationController.renderer.render(
      component_class.new(visions: visions, emission_forecast: emission_forecast, clusters: clusters),
      layout: false
    )
  end

  let(:clusters) { [ mock_cluster(id: 1, name: "Carpathian-Alpha") ] }
  let(:visions) { [ mock_insight, mock_insight(insight_type: "frost_risk", probability_score: 88) ] }
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
  end

  describe "visions delegated to ForecastCard" do
    it "renders insight_type for each vision" do
      expect(html).to include("drought")
      expect(html).to include("frost_risk")
    end

    it "renders probability scores for each vision" do
      expect(html).to include("74%")
      expect(html).to include("88%")
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
