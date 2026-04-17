# frozen_string_literal: true

require "rails_helper"

RSpec.describe Actuators::Show do
  let(:component_class) { described_class }

  def render_component(**kwargs)
    component_class.new(**kwargs).call
  end

  def mock_actuator(id: 1, device_type: "valve", state: "active", gateway_uid: "QUEEN-01")
    gateway = OpenStruct.new(uid: gateway_uid)
    commands = OpenStruct.new(last: nil)
    OpenStruct.new(id: id, device_type: device_type, state: state, gateway: gateway, commands: commands)
  end

  def mock_command(id: 1, status: "confirmed", command_payload: "OPEN_VALVE", executed_at: Time.current, user_first_name: "Ada")
    user = OpenStruct.new(first_name: user_first_name)
    OpenStruct.new(id: id, status: status, command_payload: command_payload, executed_at: executed_at, user: user)
  end

  describe "rendering" do
    let(:commands) { [mock_command(id: 1), mock_command(id: 2, status: "failed", command_payload: "RESET")] }
    let(:html) { render_component(actuator: mock_actuator, commands: commands) }

    it "renders with fade-in animation" do
      expect(html).to include("animate-in")
    end

    it "renders the Command Execution Log heading" do
      expect(html).to include("Command Execution Log")
    end

    it "displays table headers" do
      expect(html).to include("ID")
      expect(html).to include("Operator")
      expect(html).to include("Payload")
      expect(html).to include("Status")
      expect(html).to include("Executed At")
    end

    it "renders command IDs" do
      expect(html).to include("#1")
      expect(html).to include("#2")
    end

    it "displays operator name" do
      expect(html).to include("Ada")
    end

    it "displays command payload" do
      expect(html).to include("OPEN_VALVE")
      expect(html).to include("RESET")
    end

    it "renders with role=table for accessibility" do
      expect(html).to include('role="table"')
    end
  end

  describe "SYSTEM operator fallback" do
    it "displays SYSTEM when user is nil" do
      cmd = mock_command(user_first_name: nil)
      cmd_with_nil_user = OpenStruct.new(id: cmd.id, status: cmd.status, command_payload: cmd.command_payload, executed_at: cmd.executed_at, user: nil)
      html = render_component(actuator: mock_actuator, commands: [cmd_with_nil_user])
      expect(html).to include("SYSTEM")
    end
  end

  describe "command status classes" do
    it "renders emerald border for confirmed status" do
      html = render_component(actuator: mock_actuator, commands: [mock_command(status: "confirmed")])
      expect(html).to include("border-emerald-500")
      expect(html).to include("text-emerald-500")
    end

    it "renders emerald border for acknowledged status" do
      html = render_component(actuator: mock_actuator, commands: [mock_command(status: "acknowledged")])
      expect(html).to include("border-emerald-500")
    end

    it "renders blue border for sent status" do
      html = render_component(actuator: mock_actuator, commands: [mock_command(status: "sent")])
      expect(html).to include("border-blue-800")
      expect(html).to include("text-blue-400")
    end

    it "renders red border for failed status" do
      html = render_component(actuator: mock_actuator, commands: [mock_command(status: "failed")])
      expect(html).to include("border-red-900")
      expect(html).to include("text-red-500")
    end

    it "renders warning border for issued status" do
      html = render_component(actuator: mock_actuator, commands: [mock_command(status: "issued")])
      expect(html).to include("border-status-warning")
      expect(html).to include("text-status-warning-text")
    end

    it "renders zinc border for unknown status" do
      html = render_component(actuator: mock_actuator, commands: [mock_command(status: "unknown_status")])
      expect(html).to include("border-zinc-800")
      expect(html).to include("text-zinc-600")
    end
  end

  describe "executed_at formatting" do
    it "formats execution timestamp" do
      time = Time.new(2024, 3, 15, 14, 30, 45)
      html = render_component(actuator: mock_actuator, commands: [mock_command(executed_at: time)])
      expect(html).to include("15.03.24 // 14:30:45")
    end

    it "displays --- when executed_at is nil" do
      html = render_component(actuator: mock_actuator, commands: [mock_command(executed_at: nil)])
      expect(html).to include("---")
    end
  end

  describe "best practices compliance" do
    let(:html) { render_component(actuator: mock_actuator, commands: [mock_command]) }

    it "uses text-tiny and text-micro for typography" do
      expect(html).to include("text-tiny")
      expect(html).to include("text-micro")
    end

    it "uses uppercase tracking for section headers" do
      expect(html).to include("tracking-widest")
    end
  end
end
