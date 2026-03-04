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
end
