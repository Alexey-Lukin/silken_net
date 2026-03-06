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

  # =========================================================================
  # 🛡️ IDEMPOTENCY TOKEN
  # =========================================================================
  describe "idempotency_token" do
    it "auto-generates UUID before validation on create" do
      command = ActuatorCommand.new(
        actuator: actuator,
        command_payload: "OPEN",
        duration_seconds: 60
      )
      command.valid?
      expect(command.idempotency_token).to be_present
      expect(command.idempotency_token).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
    end

    it "preserves explicitly set idempotency_token" do
      custom_token = SecureRandom.uuid
      command = ActuatorCommand.new(
        actuator: actuator,
        command_payload: "OPEN",
        duration_seconds: 60,
        idempotency_token: custom_token
      )
      command.valid?
      expect(command.idempotency_token).to eq(custom_token)
    end

    it "enforces uniqueness of idempotency_token" do
      token = SecureRandom.uuid
      create(:actuator_command, actuator: actuator, idempotency_token: token)

      duplicate = ActuatorCommand.new(
        actuator: actuator,
        command_payload: "CLOSE",
        duration_seconds: 30,
        idempotency_token: token
      )
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:idempotency_token]).to be_present
    end
  end

  # =========================================================================
  # 🚦 PRIORITY
  # =========================================================================
  describe "priority" do
    it "defaults to low" do
      command = ActuatorCommand.new(
        actuator: actuator,
        command_payload: "OPEN",
        duration_seconds: 60
      )
      expect(command.priority).to eq("low")
    end

    it "accepts all priority levels" do
      %w[low medium high].each do |level|
        command = ActuatorCommand.new(
          actuator: actuator,
          command_payload: "OPEN",
          duration_seconds: 60,
          priority: level
        )
        expect(command).to be_valid, "Expected priority '#{level}' to be valid"
      end
    end

    it "provides priority query methods" do
      command = ActuatorCommand.new(priority: :high)
      expect(command).to be_priority_high
      expect(command).not_to be_priority_low
    end
  end

  # =========================================================================
  # ⏱️ EXPIRES_AT (TTL)
  # =========================================================================
  describe "expires_at (TTL)" do
    it "accepts nil expires_at (no TTL)" do
      command = ActuatorCommand.new(
        actuator: actuator,
        command_payload: "OPEN",
        duration_seconds: 60,
        expires_at: nil
      )
      expect(command).to be_valid
    end

    it "accepts future expires_at" do
      command = ActuatorCommand.new(
        actuator: actuator,
        command_payload: "OPEN",
        duration_seconds: 60,
        expires_at: 30.minutes.from_now
      )
      expect(command).to be_valid
    end

    it "rejects past expires_at on create" do
      command = ActuatorCommand.new(
        actuator: actuator,
        command_payload: "OPEN",
        duration_seconds: 60,
        expires_at: 1.minute.ago
      )
      expect(command).not_to be_valid
      expect(command.errors[:expires_at]).to be_present
    end

    it "reports expired? correctly" do
      command = ActuatorCommand.new(expires_at: 1.minute.ago)
      expect(command).to be_expired

      command2 = ActuatorCommand.new(expires_at: 30.minutes.from_now)
      expect(command2).not_to be_expired

      command3 = ActuatorCommand.new(expires_at: nil)
      expect(command3).not_to be_expired
    end
  end

  # =========================================================================
  # 📈 ORGANIZATION DENORMALIZATION
  # =========================================================================
  describe "organization denormalization" do
    it "auto-fills organization_id from actuator chain on create" do
      org = gateway.cluster.organization
      command = ActuatorCommand.new(
        actuator: actuator,
        command_payload: "OPEN",
        duration_seconds: 60
      )
      command.valid?
      expect(command.organization_id).to eq(org.id)
    end

    it "preserves explicitly set organization_id" do
      other_org = create(:organization)
      command = ActuatorCommand.new(
        actuator: actuator,
        command_payload: "OPEN",
        duration_seconds: 60,
        organization_id: other_org.id
      )
      command.valid?
      expect(command.organization_id).to eq(other_org.id)
    end
  end

  # =========================================================================
  # SCOPES
  # =========================================================================
  describe "scopes" do
    describe ".expired" do
      it "returns only pending commands past their expires_at" do
        # expired issued command
        expired_cmd = create(:actuator_command, actuator: actuator, expires_at: 1.hour.from_now)
        expired_cmd.update_columns(expires_at: 1.minute.ago) # bypass validation

        # non-expired issued command
        fresh_cmd = create(:actuator_command, actuator: actuator, expires_at: 1.hour.from_now)

        # expired but already confirmed (should NOT appear)
        confirmed_cmd = create(:actuator_command, actuator: actuator, expires_at: 1.hour.from_now)
        confirmed_cmd.update_columns(status: ActuatorCommand.statuses[:confirmed], expires_at: 1.minute.ago)

        expired_results = ActuatorCommand.expired
        expect(expired_results).to include(expired_cmd)
        expect(expired_results).not_to include(fresh_cmd)
        expect(expired_results).not_to include(confirmed_cmd)
      end
    end

    describe ".by_priority" do
      it "orders by priority descending, then by created_at ascending" do
        low_cmd = create(:actuator_command, actuator: actuator, priority: :low)
        high_cmd = create(:actuator_command, actuator: actuator, priority: :high)
        medium_cmd = create(:actuator_command, actuator: actuator, priority: :medium)

        ordered = ActuatorCommand.by_priority
        expect(ordered.first).to eq(high_cmd)
        expect(ordered.last).to eq(low_cmd)
      end
    end
  end

  # =========================================================================
  # DISPATCH EXPIRATION CHECK
  # =========================================================================
  describe "dispatch_to_edge! expiration check" do
    it "marks expired command as failed instead of dispatching" do
      allow_any_instance_of(ActuatorCommand).to receive(:broadcast_prepend_to_activity_feed)

      command = create(:actuator_command, actuator: actuator, expires_at: 5.minutes.from_now)
      # Simulate time passing so the command expires before dispatch
      command.update_columns(expires_at: 1.second.ago)
      command.send(:dispatch_to_edge!)

      command.reload
      expect(command.status).to eq("failed")
      expect(command.error_message).to include("протермінована")
    end
  end
end
