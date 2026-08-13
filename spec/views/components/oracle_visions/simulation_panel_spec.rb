# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe OracleVisions::SimulationPanel do
  # [TEST.12] Реальний незбережений `Cluster` замість OpenStruct із рукописними
  # `model_name`/`to_key`/`to_param`: саме ця трійця робила фікстуру нечутливою до
  # того, що віддає модель — а `<option value>` будується з НЕЇ.
  def build_cluster(id:, name:)
    Cluster.new(id: id, name: name)
  end

  def render_component(clusters:)
    ApplicationController.renderer.render(component_class.new(clusters: clusters), layout: false)
  end

  let(:clusters) do
    [
      build_cluster(id: 1, name: "Carpathian-Alpha"),
      build_cluster(id: 2, name: "Podillia-Beta")
    ]
  end

  let(:html) { render_component(clusters: clusters) }

  describe "header" do
    it "renders the Simulation Engine heading" do
      expect(html).to include("Simulation Engine")
    end

    it "renders the What-If subtitle" do
      expect(html).to include("What-If?")
    end
  end

  describe "cluster selector" do
    it "renders a cluster select dropdown" do
      expect(html).to include("<select")
      expect(html).to include('name="cluster_id"')
    end

    it "includes all cluster names as options" do
      expect(html).to include("Sector: Carpathian-Alpha")
      expect(html).to include("Sector: Podillia-Beta")
    end

    it "renders options with cluster IDs as values" do
      expect(html).to include('value="1"')
      expect(html).to include('value="2"')
    end

    it "labels the selector as Target Sector" do
      expect(html).to include("Target Sector")
    end
  end

  describe "sliders" do
    it "renders the Temp Offset slider" do
      expect(html).to include("Temp Offset")
      expect(html).to include('name="variables[temp_offset]"')
    end

    it "renders temp_offset with correct range (-10 to 10)" do
      expect(html).to include('min="-10"')
      expect(html).to include('max="10"')
    end

    it "renders the Humidity Drop slider" do
      expect(html).to include("Humidity Drop")
      expect(html).to include('name="variables[humidity_drop]"')
    end

    it "renders humidity_drop with correct range (-50 to 0)" do
      expect(html).to include('min="-50"')
      expect(html).to include('max="0"')
    end

    it "renders the Sap Flow Bias slider" do
      expect(html).to include("Sap Flow Bias")
      expect(html).to include('name="variables[sap_bias]"')
    end

    it "renders sap_bias with correct range (-20 to 20)" do
      expect(html).to include('min="-20"')
      expect(html).to include('max="20"')
    end
  end

  describe "submit button" do
    it "renders the Neural Simulation submit button" do
      expect(html).to include("Invoke Neural Simulation")
    end

    it "button has type submit" do
      expect(html).to include('type="submit"')
    end
  end

  describe "form action" do
    it "posts to the simulate oracle visions path" do
      expect(html).to include("/oracle_visions/simulate")
    end

    it "targets the simulation_results turbo frame" do
      expect(html).to include("simulation_results")
    end
  end
end
