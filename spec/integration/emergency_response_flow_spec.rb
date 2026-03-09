# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Emergency response and actuator command flow" do
  let(:organization) { create(:organization) }
  let(:cluster) { create(:cluster, organization: organization) }
  let(:tree_family) { create(:tree_family) }

  before do
    allow_any_instance_of(Tree).to receive(:broadcast_map_update)
    allow_any_instance_of(Wallet).to receive(:broadcast_balance_update)
    allow(AlertNotificationWorker).to receive(:perform_async)
    allow(ActuatorCommandWorker).to receive(:perform_async)
  end

  describe "EmergencyResponseService dispatches actuator commands" do
    let!(:tree) { create(:tree, cluster: cluster, tree_family: tree_family, latitude: 49.4, longitude: 32.0) }
    let!(:gateway) { create(:gateway, :online, cluster: cluster, latitude: 49.41, longitude: 32.01) }
    let!(:water_valve) { create(:actuator, :water_valve, gateway: gateway) }

    it "dispatches water valve command for drought alert" do
      alert = create(:ews_alert, :drought, cluster: cluster, tree: tree)

      # Drought: OPEN_VALVE for 7200s = 2 chunks of 3600s
      expect { EmergencyResponseService.call(alert) }
        .to change(ActuatorCommand, :count).by(2)

      cmds = ActuatorCommand.where(command_payload: "OPEN_VALVE")
      expect(cmds.count).to eq(2)
      expect(cmds.pluck(:duration_seconds).uniq).to eq([ 3600 ])
      expect(cmds.first.priority).to eq("high")
      expect(cmds.first.actuator).to eq(water_valve)
    end

    it "dispatches water valve and fire siren for fire alert" do
      fire_siren = create(:actuator, :fire_siren, gateway: gateway)
      alert = create(:ews_alert, :fire, cluster: cluster, tree: tree)

      expect { EmergencyResponseService.call(alert) }
        .to change(ActuatorCommand, :count).by_at_least(2)

      payloads = ActuatorCommand.pluck(:command_payload)
      expect(payloads).to include("OPEN_VALVE")
      expect(payloads).to include("ACTIVATE_SIREN")
    end

    it "does not dispatch commands when no actuators are available" do
      # Gateway offline
      gateway.update_columns(last_seen_at: 2.hours.ago)

      alert = create(:ews_alert, :fire, cluster: cluster, tree: tree)

      expect { EmergencyResponseService.call(alert) }
        .not_to change(ActuatorCommand, :count)
    end

    it "chunks long durations into MAX_COMMAND_DURATION pieces" do
      alert = create(:ews_alert, :fire, cluster: cluster, tree: tree)

      EmergencyResponseService.call(alert)

      # Fire: OPEN_VALVE for 14400s = 4 chunks of 3600s
      valve_cmds = ActuatorCommand.where(command_payload: "OPEN_VALVE")
      expect(valve_cmds.count).to eq(4)
      expect(valve_cmds.pluck(:duration_seconds).uniq).to eq([ 3600 ])
    end
  end

  describe "ActuatorCommand lifecycle" do
    let!(:gateway) { create(:gateway, :online, cluster: cluster) }
    let!(:actuator) { create(:actuator, :water_valve, gateway: gateway) }

    it "auto-assigns idempotency token on create" do
      cmd = create(:actuator_command, actuator: actuator, expires_at: 30.minutes.from_now)
      expect(cmd.idempotency_token).to be_present
      expect(cmd.idempotency_token).to match(/\A[0-9a-f-]{36}\z/)
    end

    it "denormalizes organization_id from actuator chain" do
      cmd = create(:actuator_command, actuator: actuator, expires_at: 30.minutes.from_now)
      expect(cmd.organization_id).to eq(organization.id)
    end

    it "auto-sets override priority for STOP commands" do
      cmd = build(:actuator_command, actuator: actuator, command_payload: "STOP",
                                     priority: :low, expires_at: 30.minutes.from_now)
      cmd.valid?
      expect(cmd.priority).to eq("override")
    end

    it "auto-sets override priority for EMERGENCY_SHUTDOWN" do
      cmd = build(:actuator_command, actuator: actuator, command_payload: "EMERGENCY_SHUTDOWN",
                                     priority: :low, expires_at: 30.minutes.from_now)
      cmd.valid?
      expect(cmd.priority).to eq("override")
    end

    it "cancels pending commands on override" do
      pending_cmd = create(:actuator_command, actuator: actuator, status: :issued,
                                              expires_at: 30.minutes.from_now)
      expect(pending_cmd.status).to eq("issued")

      _override_cmd = create(:actuator_command, actuator: actuator, command_payload: "STOP",
                                                duration_seconds: 10, expires_at: 30.minutes.from_now)

      pending_cmd.reload
      expect(pending_cmd.status).to eq("failed")
      expect(pending_cmd.error_message).to include("override")
    end

    it "validates duration within safety envelope" do
      actuator.update!(max_active_duration_s: 120)
      cmd = build(:actuator_command, actuator: actuator, duration_seconds: 300,
                                     expires_at: 30.minutes.from_now)
      expect(cmd).not_to be_valid
      expect(cmd.errors[:duration_seconds]).to be_present
    end
  end

  describe "Actuator state management" do
    let!(:gateway) { create(:gateway, :online, cluster: cluster) }
    let!(:actuator) { create(:actuator, :water_valve, gateway: gateway) }

    it "marks actuator active and updates gateway pulse" do
      actuator.mark_active!
      expect(actuator.reload.state).to eq("active")
      expect(actuator.last_activated_at).to be_present
    end

    it "returns to idle state" do
      actuator.mark_active!
      actuator.mark_idle!
      expect(actuator.reload.state).to eq("idle")
    end

    it "creates system fault alert on require_maintenance!" do
      expect { actuator.require_maintenance!("CoAP timeout") }
        .to change(EwsAlert, :count).by(1)

      expect(actuator.reload.state).to eq("maintenance_needed")
      alert = EwsAlert.last
      expect(alert.alert_type).to eq("system_fault")
      expect(alert.message).to include("CoAP timeout")
    end

    it "checks ready_for_deployment? correctly" do
      expect(actuator.ready_for_deployment?).to be true

      actuator.mark_active!
      expect(actuator.ready_for_deployment?).to be false
    end
  end
end
