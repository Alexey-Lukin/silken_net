# frozen_string_literal: true

require "rails_helper"

RSpec.describe Actuator, type: :model do
  before do
    allow_any_instance_of(EwsAlert).to receive(:dispatch_notifications!)
    allow_any_instance_of(EwsAlert).to receive(:broadcast_status_change)
    allow_any_instance_of(EwsAlert).to receive(:broadcast_alert_update)
  end

  # =========================================================================
  # VALIDATIONS
  # =========================================================================
  describe "validations" do
    it "is valid with default factory attributes" do
      expect(build(:actuator)).to be_valid
    end

    it "requires name" do
      expect(build(:actuator, name: nil)).not_to be_valid
    end

    it "requires device_type" do
      actuator = build(:actuator)
      actuator.device_type = nil
      expect(actuator).not_to be_valid
    end

    it "requires endpoint" do
      expect(build(:actuator, endpoint: nil)).not_to be_valid
    end

    it "enforces endpoint uniqueness within the same gateway" do
      gateway  = create(:gateway)
      create(:actuator, gateway: gateway, endpoint: "coap/valve/1")
      duplicate = build(:actuator, gateway: gateway, endpoint: "coap/valve/1")

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:endpoint]).to be_present
    end

    it "allows the same endpoint on different gateways" do
      create(:actuator, endpoint: "coap/valve/1")
      second = build(:actuator, endpoint: "coap/valve/1")

      expect(second).to be_valid
    end

    it "rejects negative max_active_duration_s" do
      expect(build(:actuator, max_active_duration_s: -1)).not_to be_valid
    end

    it "rejects zero max_active_duration_s" do
      expect(build(:actuator, max_active_duration_s: 0)).not_to be_valid
    end

    it "allows nil max_active_duration_s" do
      expect(build(:actuator, max_active_duration_s: nil)).to be_valid
    end

    it "accepts positive max_active_duration_s" do
      expect(build(:actuator, max_active_duration_s: 60)).to be_valid
    end

    it "rejects negative estimated_mj_per_action" do
      expect(build(:actuator, estimated_mj_per_action: -1)).not_to be_valid
    end

    it "allows nil estimated_mj_per_action" do
      expect(build(:actuator, estimated_mj_per_action: nil)).to be_valid
    end

    it "allows zero estimated_mj_per_action" do
      expect(build(:actuator, estimated_mj_per_action: 0)).to be_valid
    end
  end

  # =========================================================================
  # ENUMS
  # =========================================================================
  describe "enums" do
    it "defines device_type values with prefix" do
      actuator = build(:actuator)
      expect(actuator).to respond_to(:device_type_water_valve?)
      expect(actuator).to respond_to(:device_type_fire_siren?)
      expect(actuator).to respond_to(:device_type_seismic_beacon?)
      expect(actuator).to respond_to(:device_type_drone_launcher?)
    end

    it "defines state values without prefix" do
      actuator = build(:actuator)
      expect(actuator).to respond_to(:idle?)
      expect(actuator).to respond_to(:active?)
      expect(actuator).to respond_to(:offline?)
      expect(actuator).to respond_to(:maintenance_needed?)
    end
  end

  # =========================================================================
  # SCOPES
  # =========================================================================
  describe ".operational" do
    it "returns only idle actuators" do
      idle_one   = create(:actuator, state: :idle)
      active_one = create(:actuator, state: :active)
      offline    = create(:actuator, state: :offline)

      expect(described_class.operational).to include(idle_one)
      expect(described_class.operational).not_to include(active_one, offline)
    end
  end

  # =========================================================================
  # INSTANCE METHODS
  # =========================================================================
  describe "#ready_for_deployment?" do
    it "returns false when not idle" do
      gateway  = create(:gateway, :online)
      actuator = create(:actuator, gateway: gateway, state: :active)

      expect(actuator.ready_for_deployment?).to be false
    end

    it "returns false when gateway is offline" do
      gateway  = create(:gateway, :offline)
      actuator = create(:actuator, gateway: gateway, state: :idle)
      allow(gateway).to receive_messages(online?: false, updating?: false)

      expect(actuator.ready_for_deployment?).to be false
    end

    it "returns false when gateway is updating" do
      gateway  = create(:gateway, :online)
      actuator = create(:actuator, gateway: gateway, state: :idle)
      allow(gateway).to receive_messages(online?: true, updating?: true)

      expect(actuator.ready_for_deployment?).to be false
    end

    it "returns true when idle and gateway is online and not updating" do
      gateway  = create(:gateway, :online)
      actuator = create(:actuator, gateway: gateway, state: :idle)
      allow(gateway).to receive_messages(online?: true, updating?: false)

      expect(actuator.ready_for_deployment?).to be true
    end
  end

  describe "#mark_active!" do
    it "changes state to active" do
      actuator = create(:actuator, state: :idle)

      actuator.mark_active!

      expect(actuator.reload.state).to eq("active")
    end

    it "records last_activated_at timestamp" do
      actuator = create(:actuator, state: :idle)

      freeze_time do
        actuator.mark_active!
        expect(actuator.reload.last_activated_at).to be_within(1.second).of(Time.current)
      end
    end

    it "touches the gateway last_seen_at" do
      gateway  = create(:gateway, last_seen_at: 10.minutes.ago)
      actuator = create(:actuator, gateway: gateway, state: :idle)

      actuator.mark_active!

      expect(gateway.reload.last_seen_at).to be_within(2.seconds).of(Time.current)
    end
  end

  describe "#mark_idle!" do
    it "changes state back to idle" do
      actuator = create(:actuator, state: :active)

      actuator.mark_idle!

      expect(actuator.reload.state).to eq("idle")
    end
  end

  describe "#require_maintenance!" do
    it "changes state to maintenance_needed" do
      actuator = create(:actuator, state: :active)

      actuator.require_maintenance!

      expect(actuator.reload.state).to eq("maintenance_needed")
    end

    it "creates a critical EwsAlert when the actuator has a cluster" do
      cluster  = create(:cluster)
      gateway  = create(:gateway, cluster: cluster)
      actuator = create(:actuator, gateway: gateway)

      expect {
        actuator.require_maintenance!("Test fault")
      }.to change(EwsAlert, :count).by(1)

      alert = EwsAlert.last
      expect(alert.cluster).to eq(cluster)
      expect(alert).to be_alert_type_system_fault
      expect(alert).to be_severity_critical
      expect(alert.message).to include(actuator.name)
      expect(alert.message).to include("Test fault")
    end

    it "does not create an EwsAlert when the actuator has no cluster" do
      gateway  = create(:gateway)
      actuator = create(:actuator, gateway: gateway)
      allow(gateway).to receive(:cluster_id).and_return(nil)

      expect {
        actuator.require_maintenance!
      }.not_to change(EwsAlert, :count)
    end

    it "uses the default reason when none is provided" do
      cluster  = create(:cluster)
      gateway  = create(:gateway, cluster: cluster)
      actuator = create(:actuator, gateway: gateway)

      actuator.require_maintenance!

      expect(EwsAlert.last.message).to include("Невідома помилка CoAP")
    end
  end

  # =========================================================================
  # AASM STATE MACHINE
  # =========================================================================
  describe "AASM state machine" do
    let(:gateway) { create(:gateway, :online) }
    let(:actuator) { create(:actuator, gateway: gateway, state: :idle) }

    describe "initial state" do
      it "starts as idle" do
        expect(build(:actuator, gateway: gateway)).to be_idle
      end
    end

    describe "#activate! (via mark_active!)" do
      it "transitions from idle to active" do
        freeze_time do
          actuator.mark_active!
          actuator.reload
          expect(actuator).to be_active
          expect(actuator.last_activated_at).to be_within(1.second).of(Time.current)
        end
      end

      it "rejects transition from maintenance_needed" do
        actuator.update_columns(state: Actuator.states[:maintenance_needed])
        actuator.reload
        expect { actuator.mark_active! }.to raise_error(AASM::InvalidTransition)
      end
    end

    describe "#deactivate! (via mark_idle!)" do
      it "transitions from active to idle" do
        actuator.update_columns(state: Actuator.states[:active])
        actuator.reload
        actuator.mark_idle!
        expect(actuator.reload).to be_idle
      end

      it "transitions from maintenance_needed to idle (repair)" do
        actuator.update_columns(state: Actuator.states[:maintenance_needed])
        actuator.reload
        actuator.mark_idle!
        expect(actuator.reload).to be_idle
      end
    end

    describe "#report_fault! (via require_maintenance!)" do
      it "transitions from idle to maintenance_needed and creates EWS alert" do
        allow_any_instance_of(EwsAlert).to receive(:dispatch_notifications!)
        actuator.require_maintenance!("CoAP timeout")
        expect(actuator.reload).to be_maintenance_needed
      end
    end

    describe "may_ query methods" do
      it "reports valid transitions from idle" do
        expect(actuator.may_activate?).to be true
        expect(actuator.may_deactivate?).to be false
        expect(actuator.may_report_fault?).to be true
      end
    end
  end
end
