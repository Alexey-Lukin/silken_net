# frozen_string_literal: true

require "rails_helper"

RSpec.describe Actuators::Card do
  let(:component_class) { described_class }

  def render_component(**kwargs)
    component_class.new(**kwargs).call
  end

  def mock_actuator(id: 1, device_type: "valve", state: "active", gateway_uid: "QUEEN-01")
    gateway = OpenStruct.new(uid: gateway_uid)
    commands = OpenStruct.new(last: nil)
    OpenStruct.new(id: id, device_type: device_type, state: state, gateway: gateway, commands: commands)
  end

  def mock_command(status: "confirmed")
    OpenStruct.new(status: status)
  end

  describe "rendering" do
    let(:html) { render_component(actuator: mock_actuator) }

    it "renders the actuator id in the element id" do
      expect(html).to include("actuator_1")
    end

    it "displays the device type" do
      expect(html).to include("valve")
    end

    it "displays the gateway UID in the header" do
      expect(html).to include("QUEEN-01")
    end
  end

  describe "status LED" do
    it "renders emerald glow for active state" do
      html = render_component(actuator: mock_actuator(state: "active"))
      expect(html).to include("bg-emerald-500")
    end

    it "renders red pulse for maintenance_needed state" do
      html = render_component(actuator: mock_actuator(state: "maintenance_needed"))
      expect(html).to include("bg-red-600")
      expect(html).to include("animate-pulse")
    end

    it "renders dark red for offline state" do
      html = render_component(actuator: mock_actuator(state: "offline"))
      expect(html).to include("bg-red-900")
    end

    it "renders gray for unknown state" do
      html = render_component(actuator: mock_actuator(state: "unknown"))
      expect(html).to include("bg-gray-800")
    end
  end

  describe "status matrix" do
    it "displays the physical state" do
      html = render_component(actuator: mock_actuator(state: "active"))
      expect(html).to include("Physical State:")
      expect(html).to include("active")
    end

    it "displays last command status" do
      html = render_component(actuator: mock_actuator, last_command: mock_command(status: "confirmed"))
      expect(html).to include("confirmed")
    end

    it "displays IDLE when no last command" do
      html = render_component(actuator: mock_actuator)
      expect(html).to include("IDLE")
    end

    it "highlights failed command status with danger accent" do
      html = render_component(actuator: mock_actuator, last_command: mock_command(status: "failed"))
      expect(html).to include("text-status-danger-accent")
    end
  end

  describe "best practices compliance" do
    let(:html) { render_component(actuator: mock_actuator) }

    it "uses extracted card_container_classes method" do
      expect(html).to include("border-gaia-border")
      expect(html).to include("bg-gaia-surface")
      expect(html).to include("hover:border-gaia-primary")
      expect(html).to include("transition-all")
    end

    it "uses semantic text tokens instead of arbitrary sizes for content" do
      expect(html).to include("text-micro")
      expect(html).to include("text-tiny")
    end

    it "uses tracking-widest for uppercase microcopy" do
      expect(html).to include("tracking-widest")
    end
  end
end
