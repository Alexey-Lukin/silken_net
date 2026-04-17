# frozen_string_literal: true

require "rails_helper"

RSpec.describe Actuators::Index do
  let(:component_class) { described_class }

  def render_component(**kwargs)
    ApplicationController.renderer.render(component_class.new(**kwargs), layout: false)
  end

  def mock_cluster(name: "Amazon-Alpha")
    OpenStruct.new(id: 1, name: name)
  end

  def mock_pagy(count: 3, page: 1)
    pagy = OpenStruct.new(count: count, page: page, last: 1, from: 1, to: count, prev: nil, next: nil, vars: { items: 21 })
    pagy.define_singleton_method(:series) { [1] }
    pagy
  end

  def mock_actuator(id: 1, device_type: "valve", state: "active", gateway_uid: "QUEEN-01")
    gateway = OpenStruct.new(uid: gateway_uid)
    commands = OpenStruct.new(last: nil)
    OpenStruct.new(id: id, device_type: device_type, state: state, gateway: gateway, commands: commands)
  end

  describe "rendering with actuators" do
    let(:actuators) { [mock_actuator(id: 1), mock_actuator(id: 2)] }
    let(:html) { render_component(cluster: mock_cluster, actuators: actuators, pagy: mock_pagy(count: 2)) }

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
      html = render_component(cluster: mock_cluster, actuators: [mock_actuator], pagy: mock_pagy, active_count: 5)
      expect(html).to include("Active Nodes")
    end
  end

  describe "empty state" do
    let(:html) { render_component(cluster: mock_cluster, actuators: [], pagy: mock_pagy(count: 0)) }

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
    let(:html) { render_component(cluster: mock_cluster, actuators: [mock_actuator], pagy: mock_pagy) }

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
