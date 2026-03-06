# frozen_string_literal: true

require "rails_helper"

RSpec.describe ActuatorCommand, type: :model do
  before do
    allow(ActuatorCommandWorker).to receive(:perform_async)
    allow_any_instance_of(ActuatorCommand).to receive(:broadcast_prepend_to_activity_feed)
  end

  let(:gateway) { create(:gateway, :online) }
  let(:actuator) { create(:actuator, gateway: gateway) }

  describe "command_payload validation" do
    it "accepts valid payload format ACTION" do
      command = ActuatorCommand.new(
        actuator: actuator,
        command_payload: "OPEN",
        duration_seconds: 60,
        status: :issued
      )
      expect(command).to be_valid
    end

    it "accepts valid payload format ACTION:value" do
      command = ActuatorCommand.new(
        actuator: actuator,
        command_payload: "OPEN:60",
        duration_seconds: 60,
        status: :issued
      )
      expect(command).to be_valid
    end

    it "accepts payload with underscores" do
      command = ActuatorCommand.new(
        actuator: actuator,
        command_payload: "EMERGENCY_STOP",
        duration_seconds: 60,
        status: :issued
      )
      expect(command).to be_valid
    end

    it "rejects payload with invalid characters" do
      command = ActuatorCommand.new(
        actuator: actuator,
        command_payload: "DROP_DATABASE; --",
        duration_seconds: 60,
        status: :issued
      )
      expect(command).not_to be_valid
      expect(command.errors[:command_payload]).to be_present
    end

    it "rejects payload with lowercase characters" do
      command = ActuatorCommand.new(
        actuator: actuator,
        command_payload: "open:60",
        duration_seconds: 60,
        status: :issued
      )
      expect(command).not_to be_valid
    end

    it "rejects empty payload" do
      command = ActuatorCommand.new(
        actuator: actuator,
        command_payload: "",
        duration_seconds: 60,
        status: :issued
      )
      expect(command).not_to be_valid
    end
  end

  describe "safety envelope validation" do
    it "rejects duration exceeding actuator max_active_duration_s" do
      limited_actuator = create(:actuator, gateway: gateway, max_active_duration_s: 120)
      command = ActuatorCommand.new(
        actuator: limited_actuator,
        command_payload: "OPEN",
        duration_seconds: 180,
        status: :issued
      )
      expect(command).not_to be_valid
      expect(command.errors[:duration_seconds]).to be_present
    end

    it "accepts duration within actuator max_active_duration_s" do
      limited_actuator = create(:actuator, gateway: gateway, max_active_duration_s: 120)
      command = ActuatorCommand.new(
        actuator: limited_actuator,
        command_payload: "OPEN",
        duration_seconds: 60,
        status: :issued
      )
      expect(command).to be_valid
    end

    it "accepts duration equal to actuator max_active_duration_s" do
      limited_actuator = create(:actuator, gateway: gateway, max_active_duration_s: 120)
      command = ActuatorCommand.new(
        actuator: limited_actuator,
        command_payload: "OPEN",
        duration_seconds: 120,
        status: :issued
      )
      expect(command).to be_valid
    end

    it "skips safety envelope check when actuator has no limit" do
      unlimited_actuator = create(:actuator, gateway: gateway, max_active_duration_s: nil)
      command = ActuatorCommand.new(
        actuator: unlimited_actuator,
        command_payload: "OPEN",
        duration_seconds: 3600,
        status: :issued
      )
      expect(command).to be_valid
    end
  end
end
