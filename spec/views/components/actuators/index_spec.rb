# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Actuators::Index do
  def mock_cluster(name: "Amazon-Alpha")
    OpenStruct.new(id: 1, name: name)
  end


  # [TEST.12] Реальний незбережений `Actuator` — `device_type` ходить через справжній
  # enum, тож вигаданого `"valve"` тут більше не буває (модель приймає лише
  # `water_valve`/`fire_siren`/`seismic_beacon`/`drone_launcher`).
  def build_actuator(id: 1, device_type: :water_valve, state: :active, gateway_uid: "QUEEN-01")
    Actuator.new(id: id, device_type: device_type, state: state, gateway: Gateway.new(uid: gateway_uid))
  end

  describe "rendering with actuators" do
    let(:actuators) { [ build_actuator(id: 1), build_actuator(id: 2) ] }
    let(:html) { render_component(cluster: mock_cluster, actuators: actuators, pagy: mock_pagy(count: 2, last: 1)) }

    it "renders the main container with animation" do
      expect(html).to include("animate-in")
    end

    it "displays the cluster name in the header" do
      expect(html).to include("Amazon-Alpha")
    end

    it "shows the Hardware Interaction Layer subtitle" do
      expect(html).to include("Hardware Interaction Layer")
    end

    it "displays the total units count from pagy" do
      expect(html).to include("Total Units")
    end

    it "renders the grid layout for actuator cards" do
      expect(html).to include("grid-cols-1")
    end

    it "displays ACTUATORS watermark" do
      expect(html).to include("ACTUATORS")
    end

    it "renders the Sector Matrix title with cluster name" do
      expect(html).to include("Sector Matrix // Amazon-Alpha")
    end

    it "displays active count stat" do
      html = render_component(cluster: mock_cluster, actuators: [ build_actuator ], pagy: mock_pagy(last: 1), active_count: 5)
      expect(html).to include("Active Nodes")
    end
  end

  describe "empty state" do
    let(:html) { render_component(cluster: mock_cluster, actuators: [], pagy: mock_pagy(count: 0, last: 1)) }

    it "renders empty state message when no actuators" do
      expect(html).to include("No actuator nodes provisioned in this sector.")
    end

    it "shows the deploy instruction" do
      expect(html).to include("Deploy hardware to begin monitoring.")
    end

    it "renders the gear icon for empty state" do
      expect(html).to include("⚙")
    end
  end

  describe "best practices compliance" do
    let(:html) { render_component(cluster: mock_cluster, actuators: [ build_actuator ], pagy: mock_pagy(last: 1)) }

    it "uses text-tiny for uppercase microcopy" do
      expect(html).to include("text-tiny")
    end

    it "uses tracking for uppercase labels" do
      expect(html).to include("tracking-")
    end

    it "uses emerald color scheme" do
      expect(html).to include("text-emerald-700")
    end
  end
end
