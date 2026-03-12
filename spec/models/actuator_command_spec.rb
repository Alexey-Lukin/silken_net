# frozen_string_literal: true

require "rails_helper"

RSpec.describe ActuatorCommand, type: :model do
  before do
    allow(ActuatorCommandWorker).to receive(:perform_async)
    allow_any_instance_of(described_class).to receive(:broadcast_prepend_to_activity_feed)
  end

  let(:gateway) { create(:gateway, :online) }
  let(:actuator) { create(:actuator, gateway: gateway) }

  describe "command_payload validation" do
    it "accepts valid payload format ACTION" do
      command = described_class.new(
        actuator: actuator,
        command_payload: "OPEN",
        duration_seconds: 60,
        status: :issued
      )
      expect(command).to be_valid
    end

    it "accepts valid payload format ACTION:value" do
      command = described_class.new(
        actuator: actuator,
        command_payload: "OPEN:60",
        duration_seconds: 60,
        status: :issued
      )
      expect(command).to be_valid
    end

    it "accepts payload with underscores" do
      command = described_class.new(
        actuator: actuator,
        command_payload: "EMERGENCY_STOP",
        duration_seconds: 60,
        status: :issued
      )
      expect(command).to be_valid
    end

    it "rejects payload with invalid characters" do
      command = described_class.new(
        actuator: actuator,
        command_payload: "DROP_DATABASE; --",
        duration_seconds: 60,
        status: :issued
      )
      expect(command).not_to be_valid
      expect(command.errors[:command_payload]).to be_present
    end

    it "rejects payload with lowercase characters" do
      command = described_class.new(
        actuator: actuator,
        command_payload: "open:60",
        duration_seconds: 60,
        status: :issued
      )
      expect(command).not_to be_valid
    end

    it "rejects empty payload" do
      command = described_class.new(
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
      command = described_class.new(
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
      command = described_class.new(
        actuator: limited_actuator,
        command_payload: "OPEN",
        duration_seconds: 60,
        status: :issued
      )
      expect(command).to be_valid
    end

    it "accepts duration equal to actuator max_active_duration_s" do
      limited_actuator = create(:actuator, gateway: gateway, max_active_duration_s: 120)
      command = described_class.new(
        actuator: limited_actuator,
        command_payload: "OPEN",
        duration_seconds: 120,
        status: :issued
      )
      expect(command).to be_valid
    end

    it "skips safety envelope check when actuator has no limit" do
      unlimited_actuator = create(:actuator, gateway: gateway, max_active_duration_s: nil)
      command = described_class.new(
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
      command = described_class.new(
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
      command = described_class.new(
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

      duplicate = described_class.new(
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
      command = described_class.new(
        actuator: actuator,
        command_payload: "OPEN",
        duration_seconds: 60
      )
      expect(command.priority).to eq("low")
    end

    it "accepts all priority levels" do
      %w[low medium high override].each do |level|
        command = described_class.new(
          actuator: actuator,
          command_payload: "OPEN",
          duration_seconds: 60,
          priority: level
        )
        expect(command).to be_valid, "Expected priority '#{level}' to be valid"
      end
    end

    it "provides priority query methods" do
      command = described_class.new(priority: :high)
      expect(command).to be_priority_high
      expect(command).not_to be_priority_low
    end
  end

  # =========================================================================
  # 🛑 OVERRIDE PRIORITY (STOP / EMERGENCY_SHUTDOWN)
  # =========================================================================
  describe "override priority" do
    it "auto-sets override priority for STOP command" do
      command = described_class.new(
        actuator: actuator,
        command_payload: "STOP",
        duration_seconds: 1
      )
      command.valid?
      expect(command).to be_priority_override
    end

    it "auto-sets override priority for EMERGENCY_SHUTDOWN command" do
      command = described_class.new(
        actuator: actuator,
        command_payload: "EMERGENCY_SHUTDOWN",
        duration_seconds: 1
      )
      command.valid?
      expect(command).to be_priority_override
    end

    it "auto-sets override priority for EMERGENCY_STOP command" do
      command = described_class.new(
        actuator: actuator,
        command_payload: "EMERGENCY_STOP",
        duration_seconds: 1
      )
      command.valid?
      expect(command).to be_priority_override
    end

    it "auto-sets override for STOP:value format" do
      command = described_class.new(
        actuator: actuator,
        command_payload: "STOP:0",
        duration_seconds: 1
      )
      command.valid?
      expect(command).to be_priority_override
    end

    it "does not auto-set override for regular commands" do
      command = described_class.new(
        actuator: actuator,
        command_payload: "OPEN",
        duration_seconds: 60
      )
      command.valid?
      expect(command).to be_priority_low
    end

    it "cancels all pending commands for the actuator on creation" do
      # Create two pending commands
      pending1 = create(:actuator_command, actuator: actuator, command_payload: "OPEN", duration_seconds: 60)
      pending2 = create(:actuator_command, actuator: actuator, command_payload: "OPEN:120", duration_seconds: 120)

      # Create override STOP command
      create(:actuator_command, actuator: actuator, command_payload: "STOP", duration_seconds: 1)

      # Pending commands should be cancelled
      expect(pending1.reload.status).to eq("failed")
      expect(pending1.error_message).to include("override")
      expect(pending2.reload.status).to eq("failed")
      expect(pending2.error_message).to include("override")
    end

    it "does not cancel already confirmed or failed commands" do
      confirmed = create(:actuator_command, actuator: actuator, command_payload: "OPEN", duration_seconds: 60)
      confirmed.update_columns(status: described_class.statuses[:confirmed])

      failed = create(:actuator_command, actuator: actuator, command_payload: "OPEN", duration_seconds: 60)
      failed.update_columns(status: described_class.statuses[:failed])

      create(:actuator_command, actuator: actuator, command_payload: "STOP", duration_seconds: 1)

      expect(confirmed.reload.status).to eq("confirmed")
      expect(failed.reload.status).to eq("failed")
    end

    it "does not cancel commands for other actuators" do
      other_actuator = create(:actuator, gateway: gateway)
      other_pending = create(:actuator_command, actuator: other_actuator, command_payload: "OPEN", duration_seconds: 60)

      create(:actuator_command, actuator: actuator, command_payload: "STOP", duration_seconds: 1)

      expect(other_pending.reload.status).to eq("issued")
    end
  end

  # =========================================================================
  # ⏱️ EXPIRES_AT (TTL)
  # =========================================================================
  describe "expires_at (TTL)" do
    it "accepts nil expires_at (no TTL)" do
      command = described_class.new(
        actuator: actuator,
        command_payload: "OPEN",
        duration_seconds: 60,
        expires_at: nil
      )
      expect(command).to be_valid
    end

    it "accepts future expires_at" do
      command = described_class.new(
        actuator: actuator,
        command_payload: "OPEN",
        duration_seconds: 60,
        expires_at: 30.minutes.from_now
      )
      expect(command).to be_valid
    end

    it "rejects past expires_at on create" do
      command = described_class.new(
        actuator: actuator,
        command_payload: "OPEN",
        duration_seconds: 60,
        expires_at: 1.minute.ago
      )
      expect(command).not_to be_valid
      expect(command.errors[:expires_at]).to be_present
    end

    it "reports expired? correctly" do
      command = described_class.new(expires_at: 1.minute.ago)
      expect(command).to be_expired

      command2 = described_class.new(expires_at: 30.minutes.from_now)
      expect(command2).not_to be_expired

      command3 = described_class.new(expires_at: nil)
      expect(command3).not_to be_expired
    end
  end

  # =========================================================================
  # 📈 ORGANIZATION DENORMALIZATION
  # =========================================================================
  describe "organization denormalization" do
    it "auto-fills organization_id from actuator chain on create" do
      org = gateway.cluster.organization
      command = described_class.new(
        actuator: actuator,
        command_payload: "OPEN",
        duration_seconds: 60
      )
      command.valid?
      expect(command.organization_id).to eq(org.id)
    end

    it "preserves explicitly set organization_id" do
      other_org = create(:organization)
      command = described_class.new(
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
        confirmed_cmd.update_columns(status: described_class.statuses[:confirmed], expires_at: 1.minute.ago)

        expired_results = described_class.expired
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

        ordered = described_class.by_priority
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
      allow_any_instance_of(described_class).to receive(:broadcast_prepend_to_activity_feed)

      command = create(:actuator_command, actuator: actuator, expires_at: 5.minutes.from_now)
      # Simulate time passing so the command expires before dispatch
      command.update_columns(expires_at: 1.second.ago)
      command.send(:dispatch_to_edge!)

      command.reload
      expect(command.status).to eq("failed")
      expect(command.error_message).to include("протермінована")
    end
  end

  describe "#estimated_completion_at" do
    it "returns nil when sent_at is nil" do
      command = create(:actuator_command, actuator: actuator)
      expect(command.sent_at).to be_nil
      expect(command.estimated_completion_at).to be_nil
    end

    it "returns sent_at + duration_seconds when sent_at is present" do
      command = create(:actuator_command, actuator: actuator, duration_seconds: 120)
      now = Time.current
      command.update_columns(sent_at: now)
      command.reload

      expect(command.estimated_completion_at).to be_within(1.second).of(now + 120.seconds)
    end
  end

  describe "denormalize_organization when actuator chain is nil" do
    it "handles nil gateway gracefully" do
      command = described_class.new(
        actuator: actuator,
        command_payload: "OPEN",
        duration_seconds: 60
      )
      allow(actuator).to receive(:gateway).and_return(nil)
      command.valid?
      expect(command.errors[:organization_id]).to be_empty
    end
  end

  describe "duration_within_safety_envelope when actuator is nil" do
    it "skips validation when actuator has nil max_active_duration_s" do
      unlimited = create(:actuator, gateway: gateway, max_active_duration_s: nil)
      command = described_class.new(
        actuator: unlimited,
        command_payload: "OPEN",
        duration_seconds: 3600
      )
      expect(command).to be_valid
    end

    it "skips validation when duration_seconds is nil" do
      command = described_class.new(
        actuator: actuator,
        command_payload: "OPEN",
        duration_seconds: nil
      )
      command.valid?
      expect(command.errors[:duration_seconds]).to include("can't be blank")
    end
  end

  describe "broadcast_prepend_to_activity_feed" do
    let(:organization) { gateway.cluster.organization }

    before do
      allow(Turbo::StreamsChannel).to receive(:broadcast_prepend_to)
    end

    it "broadcasts when organization is present via denormalization" do
      allow_any_instance_of(described_class).to receive(:broadcast_prepend_to_activity_feed).and_call_original

      command = create(:actuator_command, actuator: actuator)
      expect(command.organization).to eq(organization)
      expect(Turbo::StreamsChannel).to have_received(:broadcast_prepend_to).at_least(:once)
    end

    it "returns nil when organization is nil and actuator chain is nil" do
      command = build(:actuator_command, actuator: actuator)
      command.organization = nil
      allow(actuator).to receive(:gateway).and_return(nil)

      result = command.send(:broadcast_prepend_to_activity_feed)
      expect(result).to be_nil
    end
  end

  describe "denormalize_organization — actuator with no gateway" do
    it "sets organization_id to nil when gateway is nil" do
      orphan_actuator = build(:actuator, gateway: nil)
      allow(orphan_actuator).to receive(:gateway).and_return(nil)

      command = described_class.new(
        actuator: orphan_actuator,
        command_payload: "OPEN",
        duration_seconds: 60
      )
      command.send(:denormalize_organization)
      expect(command.organization_id).to be_nil
    end
  end

  describe "denormalize_organization — actuator is nil" do
    it "sets organization_id to nil when actuator is nil" do
      command = described_class.new(
        command_payload: "OPEN",
        duration_seconds: 60
      )
      command.actuator = nil
      command.send(:denormalize_organization)
      expect(command.organization_id).to be_nil
    end
  end

  describe "duration_within_safety_envelope — nil actuator safe navigation" do
    it "skips validation when actuator returns nil from safe navigation" do
      command = described_class.new(
        actuator: actuator,
        command_payload: "OPEN",
        duration_seconds: 30
      )
      allow(command).to receive(:actuator).and_return(nil)
      command.send(:duration_within_safety_envelope)
      expect(command.errors[:duration_seconds]).to be_empty
    end
  end

  describe "broadcast_prepend_to_activity_feed — fallback through gateway chain" do
    before do
      allow(Turbo::StreamsChannel).to receive(:broadcast_prepend_to)
    end

    it "falls back to actuator.gateway.cluster.organization when organization is nil" do
      allow_any_instance_of(described_class).to receive(:broadcast_prepend_to_activity_feed).and_call_original
      command = create(:actuator_command, actuator: actuator)
      command.update_columns(organization_id: nil)
      command.reload

      command.send(:broadcast_prepend_to_activity_feed)
      expect(Turbo::StreamsChannel).to have_received(:broadcast_prepend_to).at_least(:once)
    end

    it "returns nil when both organization and gateway chain are nil" do
      allow_any_instance_of(described_class).to receive(:broadcast_prepend_to_activity_feed).and_call_original
      command = create(:actuator_command, actuator: actuator)
      command.update_columns(organization_id: nil)
      command.reload

      allow(command.actuator).to receive(:gateway).and_return(nil)
      result = command.send(:broadcast_prepend_to_activity_feed)
      expect(result).to be_nil
    end
  end

  # =========================================================================
  # AASM STATE MACHINE
  # =========================================================================
  describe "AASM state machine" do
    let(:gateway) { create(:gateway, :online) }
    let(:actuator) { create(:actuator, gateway: gateway) }

    describe "initial state" do
      it "starts as issued" do
        command = build(:actuator_command, actuator: actuator, status: :issued)
        expect(command).to be_issued
      end
    end

    describe "#dispatch!" do
      it "transitions from issued to sent and sets sent_at" do
        command = create(:actuator_command, actuator: actuator)
        freeze_time do
          command.dispatch!
          command.reload
          expect(command).to be_sent
          expect(command.sent_at).to be_within(1.second).of(Time.current)
        end
      end

      it "rejects transition from acknowledged" do
        command = create(:actuator_command, actuator: actuator)
        command.update_columns(status: ActuatorCommand.statuses[:acknowledged])
        command.reload
        expect { command.dispatch! }.to raise_error(AASM::InvalidTransition)
      end
    end

    describe "#acknowledge!" do
      it "transitions from sent to acknowledged" do
        command = create(:actuator_command, actuator: actuator)
        command.update_columns(status: ActuatorCommand.statuses[:sent])
        command.reload
        command.acknowledge!
        expect(command.reload).to be_acknowledged
      end
    end

    describe "#confirm!" do
      it "transitions from acknowledged to confirmed and sets completed_at" do
        command = create(:actuator_command, actuator: actuator)
        command.update_columns(status: ActuatorCommand.statuses[:acknowledged])
        command.reload
        freeze_time do
          command.confirm!
          command.reload
          expect(command).to be_confirmed
          expect(command.completed_at).to be_within(1.second).of(Time.current)
        end
      end
    end

    describe "#fail!" do
      it "transitions from any state to failed" do
        command = create(:actuator_command, actuator: actuator)
        command.fail!("timeout")
        expect(command.reload).to be_failed
        expect(command.error_message).to eq("timeout")
      end

      it "can fail from sent state" do
        command = create(:actuator_command, actuator: actuator)
        command.update_columns(status: ActuatorCommand.statuses[:sent])
        command.reload
        command.fail!("gateway offline")
        expect(command.reload).to be_failed
      end
    end

    describe "may_ query methods" do
      it "reports valid transitions from issued" do
        command = build(:actuator_command, actuator: actuator, status: :issued)
        expect(command.may_dispatch?).to be true
        expect(command.may_confirm?).to be false
        expect(command.may_fail?).to be true
      end
    end
  end
end
