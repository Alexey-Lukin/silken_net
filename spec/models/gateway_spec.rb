# frozen_string_literal: true

require "rails_helper"

RSpec.describe Gateway, type: :model do
  describe "UID validation" do
    it "normalizes UID to uppercase" do
      gateway = build(:gateway, uid: "snet-q-00000abc")
      gateway.valid?

      expect(gateway.uid).to eq("SNET-Q-00000ABC")
    end

    it "accepts valid hardware UID format" do
      gateway = build(:gateway, uid: "SNET-Q-1A2B3C4D")
      expect(gateway).to be_valid
    end

    it "rejects UID that does not match hardware format" do
      gateway = build(:gateway, uid: "INVALID-UID")
      expect(gateway).not_to be_valid
      expect(gateway.errors[:uid]).to be_present
    end

    it "rejects UID with wrong prefix" do
      gateway = build(:gateway, uid: "GW-00000001")
      expect(gateway).not_to be_valid
    end

    it "rejects UID with wrong length" do
      gateway = build(:gateway, uid: "SNET-Q-123")
      expect(gateway).not_to be_valid
    end
  end

  describe "#mark_seen!" do
    it "updates last_seen_at" do
      gateway = create(:gateway, last_seen_at: nil)

      gateway.mark_seen!
      gateway.reload

      expect(gateway.last_seen_at).to be_within(2.seconds).of(Time.current)
    end

    it "updates ip_address when provided" do
      gateway = create(:gateway, ip_address: "10.0.0.1")

      gateway.mark_seen!(new_ip: "10.0.0.2")
      gateway.reload

      expect(gateway.ip_address).to eq("10.0.0.2")
    end

    it "updates latest_voltage_mv when provided" do
      gateway = create(:gateway)

      gateway.mark_seen!(voltage_mv: 4100)
      gateway.reload

      expect(gateway.latest_voltage_mv).to eq(4100)
    end

    it "never regresses last_seen_at (GREATEST semantics)" do
      gateway = create(:gateway)
      future_time = 1.hour.from_now

      gateway.update_columns(last_seen_at: future_time)
      gateway.mark_seen!
      gateway.reload

      expect(gateway.last_seen_at).to be_within(2.seconds).of(future_time)
    end

    it "does not modify uid when updating via mark_seen!" do
      gateway = create(:gateway)
      # mark_seen! uses update_all which bypasses callbacks and normalization
      expect { gateway.mark_seen! }.not_to change { gateway.reload.uid }
    end

    it "syncs in-memory state without reload" do
      gateway = create(:gateway, ip_address: "10.0.0.1", latest_voltage_mv: nil)

      gateway.mark_seen!(new_ip: "10.0.0.2", voltage_mv: 3800)

      expect(gateway.last_seen_at).to be_within(2.seconds).of(Time.current)
      expect(gateway.ip_address).to eq("10.0.0.2")
      expect(gateway.latest_voltage_mv).to eq(3800)
    end
  end

  describe "#online?" do
    it "returns false when last_seen_at is nil" do
      gateway = build(:gateway, last_seen_at: nil)
      expect(gateway).not_to be_online
    end

    it "returns true when recently seen" do
      gateway = build(:gateway, config_sleep_interval_s: 300, last_seen_at: 1.minute.ago)
      expect(gateway).to be_online
    end

    it "returns false when not seen within threshold" do
      gateway = build(:gateway, config_sleep_interval_s: 300, last_seen_at: 10.minutes.ago)
      expect(gateway).not_to be_online
    end

    it "uses 1.2x multiplier for leniency" do
      gateway = build(:gateway, config_sleep_interval_s: 300)
      # 300 * 1.2 = 360 seconds = 6 minutes
      gateway.last_seen_at = 5.minutes.ago
      expect(gateway).to be_online

      gateway.last_seen_at = 7.minutes.ago
      expect(gateway).not_to be_online
    end
  end

  describe "scopes" do
    it ".online returns gateways seen within threshold" do
      online_gw = create(:gateway, config_sleep_interval_s: 300, last_seen_at: 1.minute.ago)
      offline_gw = create(:gateway, config_sleep_interval_s: 300, last_seen_at: 10.minutes.ago)

      expect(described_class.online).to include(online_gw)
      expect(described_class.online).not_to include(offline_gw)
    end

    it ".offline returns gateways not seen within threshold or never seen" do
      online_gw = create(:gateway, config_sleep_interval_s: 300, last_seen_at: 1.minute.ago)
      offline_gw = create(:gateway, config_sleep_interval_s: 300, last_seen_at: 10.minutes.ago)
      never_seen = create(:gateway, config_sleep_interval_s: 300, last_seen_at: nil)

      expect(described_class.offline).to include(offline_gw, never_seen)
      expect(described_class.offline).not_to include(online_gw)
    end
  end

  describe "#battery_critical?" do
    it "returns true below LOW_POWER_MV" do
      gateway = build(:gateway, latest_voltage_mv: Gateway::LOW_POWER_MV - 1)
      expect(gateway).to be_battery_critical
    end

    it "returns false at LOW_POWER_MV" do
      gateway = build(:gateway, latest_voltage_mv: Gateway::LOW_POWER_MV)
      expect(gateway).not_to be_battery_critical
    end

    it "returns false when voltage is nil" do
      gateway = build(:gateway, latest_voltage_mv: nil)
      expect(gateway).not_to be_battery_critical
    end
  end

  describe "associations" do
    it "has trees through cluster" do
      gateway = create(:gateway)
      tree = create(:tree, cluster: gateway.cluster)

      expect(gateway.trees).to include(tree)
    end

    it "returns an empty collection when cluster has no trees" do
      gateway = create(:gateway)
      expect(gateway.trees).to be_empty
    end
  end

  describe "#system_fault?" do
    it "returns true when cluster has unresolved system_fault alerts" do
      gateway = create(:gateway)
      create(:ews_alert,
        cluster: gateway.cluster,
        alert_type: :system_fault,
        severity: :critical,
        status: :active
      )

      expect(gateway).to be_system_fault
    end

    it "returns true when battery is critical" do
      gateway = build(:gateway, latest_voltage_mv: Gateway::LOW_POWER_MV - 100, cluster: nil)
      expect(gateway).to be_system_fault
    end

    it "returns false when no faults and battery is fine" do
      gateway = create(:gateway, latest_voltage_mv: 4200)
      expect(gateway).not_to be_system_fault
    end

    it "returns false when cluster is nil" do
      gateway = build(:gateway, cluster: nil, latest_voltage_mv: 4200)
      expect(gateway).not_to be_system_fault
    end
  end

  describe "#geolocated?" do
    it "returns true when both latitude and longitude are present" do
      gateway = build(:gateway, :geolocated)
      expect(gateway).to be_geolocated
    end

    it "returns false when latitude is nil" do
      gateway = build(:gateway, latitude: nil, longitude: 32.0)
      expect(gateway).not_to be_geolocated
    end

    it "returns false when longitude is nil" do
      gateway = build(:gateway, latitude: 49.0, longitude: nil)
      expect(gateway).not_to be_geolocated
    end
  end

  describe "#next_wakeup_expected_at" do
    it "returns last_seen_at + config_sleep_interval_s" do
      seen_at = Time.current
      gateway = build(:gateway, last_seen_at: seen_at, config_sleep_interval_s: 300)

      expected = seen_at + 300.seconds
      expect(gateway.next_wakeup_expected_at).to be_within(1.second).of(expected)
    end

    it "returns nil when last_seen_at is nil" do
      gateway = build(:gateway, last_seen_at: nil)
      expect(gateway.next_wakeup_expected_at).to be_nil
    end
  end

  # =========================================================================
  # FIRMWARE UPDATE STATUS (OTA Status Tracking)
  # =========================================================================
  describe "firmware_update_status" do
    it "defaults to fw_idle" do
      gateway = build(:gateway)
      expect(gateway.firmware_update_status).to eq("fw_idle")
    end

    it "supports all OTA lifecycle states" do
      gateway = build(:gateway)
      %w[fw_idle fw_pending fw_downloading fw_verifying fw_flashing fw_failed fw_completed].each do |state|
        gateway.firmware_update_status = state
        expect(gateway.firmware_update_status).to eq(state)
      end
    end

    it "provides prefixed query methods" do
      gateway = build(:gateway, firmware_update_status: :fw_flashing)
      expect(gateway).to be_firmware_fw_flashing
      expect(gateway).not_to be_firmware_fw_idle
    end
  end

  # =========================================================================
  # AASM STATE MACHINE
  # =========================================================================
  describe "AASM state machine" do
    describe "initial state" do
      it "starts as idle" do
        expect(build(:gateway)).to be_idle
      end
    end

    describe "#wake!" do
      it "transitions from idle to active" do
        gateway = create(:gateway, state: :idle)
        gateway.wake!
        expect(gateway.reload).to be_active
      end
    end

    describe "#sleep!" do
      it "transitions from active to idle" do
        gateway = create(:gateway)
        gateway.update_columns(state: described_class.states[:active])
        gateway.reload
        gateway.sleep!
        expect(gateway.reload).to be_idle
      end
    end

    describe "#begin_update!" do
      it "transitions from idle to updating" do
        gateway = create(:gateway, state: :idle)
        gateway.begin_update!
        expect(gateway.reload).to be_updating
      end
    end

    describe "#finish_update!" do
      it "transitions from updating to idle" do
        gateway = create(:gateway)
        gateway.update_columns(state: described_class.states[:updating])
        gateway.reload
        gateway.finish_update!
        expect(gateway.reload).to be_idle
      end
    end

    describe "#report_fault!" do
      it "transitions from active to faulty" do
        gateway = create(:gateway)
        gateway.update_columns(state: described_class.states[:active])
        gateway.reload
        gateway.report_fault!
        expect(gateway.reload).to be_faulty
      end
    end

    describe "#enter_maintenance!" do
      it "transitions from idle to maintenance" do
        gateway = create(:gateway, state: :idle)
        gateway.enter_maintenance!
        expect(gateway.reload).to be_maintenance
      end
    end

    describe "#exit_maintenance!" do
      it "transitions from maintenance to idle" do
        gateway = create(:gateway)
        gateway.update_columns(state: described_class.states[:maintenance])
        gateway.reload
        gateway.exit_maintenance!
        expect(gateway.reload).to be_idle
      end
    end

    describe "may_ query methods" do
      it "reports valid transitions from idle" do
        gateway = build(:gateway, state: :idle)
        expect(gateway.may_wake?).to be true
        expect(gateway.may_sleep?).to be false
        expect(gateway.may_begin_update?).to be true
        expect(gateway.may_report_fault?).to be true
      end
    end
  end

  # =========================================================================
  # AASM FIRMWARE STATE MACHINE (from Firmwareable concern)
  # =========================================================================
  describe "AASM firmware state machine" do
    let(:gateway) { create(:gateway) }

    describe "#schedule_update!" do
      it "transitions from fw_idle to fw_pending" do
        gateway.schedule_update!
        expect(gateway.reload).to be_firmware_fw_pending
      end
    end

    describe "#start_download!" do
      it "transitions from fw_pending to fw_downloading" do
        gateway.update_columns(firmware_update_status: described_class.firmware_update_statuses[:fw_pending])
        gateway.reload
        gateway.start_download!
        expect(gateway.reload).to be_firmware_fw_downloading
      end
    end

    describe "#complete_update!" do
      it "transitions from fw_flashing to fw_completed" do
        gateway.update_columns(firmware_update_status: described_class.firmware_update_statuses[:fw_flashing])
        gateway.reload
        gateway.complete_update!
        expect(gateway.reload).to be_firmware_fw_completed
      end
    end

    describe "#fail_update!" do
      it "transitions from fw_downloading to fw_failed" do
        gateway.update_columns(firmware_update_status: described_class.firmware_update_statuses[:fw_downloading])
        gateway.reload
        gateway.fail_update!
        expect(gateway.reload).to be_firmware_fw_failed
      end
    end

    describe "#reset_firmware!" do
      it "transitions from fw_failed to fw_idle" do
        gateway.update_columns(firmware_update_status: described_class.firmware_update_statuses[:fw_failed])
        gateway.reload
        gateway.reset_firmware!
        expect(gateway.reload).to be_firmware_fw_idle
      end
    end
  end
end
