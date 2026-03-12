# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tree, type: :model do
  before do
    allow_any_instance_of(described_class).to receive(:broadcast_map_update)
  end

  describe "after_create callbacks" do
    it "creates a wallet after creation" do
      tree = create(:tree)

      expect(tree.wallet).to be_present
      expect(tree.wallet.balance).to eq(0)
    end
  end

  describe ".critical_stress scope" do
    it "returns trees with high stress from yesterday's AI insights" do
      tree = create(:tree, status: :active)
      create(:ai_insight, :daily_health_summary,
             analyzable: tree,
             target_date: Time.current.utc.to_date - 1,
             stress_index: 0.95)

      expect(described_class.critical_stress).to include(tree)
    end

    it "excludes trees with low stress" do
      tree = create(:tree, status: :active)
      create(:ai_insight, :daily_health_summary,
             analyzable: tree,
             target_date: Time.current.utc.to_date - 1,
             stress_index: 0.5)

      expect(described_class.critical_stress).not_to include(tree)
    end
  end

  describe "DID validation" do
    it "normalizes DID to uppercase" do
      tree = build(:tree, did: "snet-00000abc")
      tree.valid?

      expect(tree.did).to eq("SNET-00000ABC")
    end

    it "accepts valid hardware DID format" do
      tree = build(:tree, did: "SNET-1A2B3C4D")
      expect(tree).to be_valid
    end

    it "rejects DID that does not match hardware format" do
      tree = build(:tree, did: "INVALID-DID")
      expect(tree).not_to be_valid
      expect(tree.errors[:did]).to be_present
    end

    it "rejects DID with wrong length" do
      tree = build(:tree, did: "SNET-123")
      expect(tree).not_to be_valid
    end
  end

  describe "#mark_seen!" do
    it "updates last_seen_at" do
      tree = create(:tree)
      expect(tree.last_seen_at).to be_nil

      tree.mark_seen!
      tree.reload

      expect(tree.last_seen_at).not_to be_nil
      expect(tree.last_seen_at).to be_within(2.seconds).of(Time.current)
    end

    it "updates latest_voltage_mv when provided" do
      tree = create(:tree)

      tree.mark_seen!(4100)
      tree.reload

      expect(tree.latest_voltage_mv).to eq(4100)
    end

    it "never regresses last_seen_at (GREATEST semantics)" do
      tree = create(:tree)
      future_time = 1.hour.from_now

      tree.update_columns(last_seen_at: future_time)
      tree.mark_seen!
      tree.reload

      expect(tree.last_seen_at).to be_within(2.seconds).of(future_time)
    end
  end

  describe "#charge_percentage" do
    it "returns 0 when voltage is zero" do
      tree = build(:tree, latest_voltage_mv: nil)
      expect(tree.charge_percentage).to eq(0)
    end

    it "returns 0 at minimum voltage" do
      tree = build(:tree, latest_voltage_mv: Tree::VCAP_MIN_MV)
      expect(tree.charge_percentage).to eq(0)
    end

    it "returns 100 at maximum voltage" do
      tree = build(:tree, latest_voltage_mv: Tree::VCAP_MAX_MV)
      expect(tree.charge_percentage).to eq(100)
    end

    it "returns correct percentage for mid-range voltage" do
      mid_mv = (Tree::VCAP_MIN_MV + Tree::VCAP_MAX_MV) / 2
      tree = build(:tree, latest_voltage_mv: mid_mv)
      expect(tree.charge_percentage).to eq(50)
    end

    it "clamps below minimum to 0" do
      tree = build(:tree, latest_voltage_mv: 2000)
      expect(tree.charge_percentage).to eq(0)
    end
  end

  describe "#low_power?" do
    it "returns true below LOW_POWER_MV" do
      tree = build(:tree, latest_voltage_mv: Tree::LOW_POWER_MV - 1)
      expect(tree).to be_low_power
    end

    it "returns false at LOW_POWER_MV" do
      tree = build(:tree, latest_voltage_mv: Tree::LOW_POWER_MV)
      expect(tree).not_to be_low_power
    end

    it "returns false when voltage is zero (no data)" do
      tree = build(:tree, latest_voltage_mv: nil)
      expect(tree).not_to be_low_power
    end
  end

  describe "#ionic_voltage" do
    it "returns latest_voltage_mv when present" do
      tree = build(:tree, latest_voltage_mv: 4200)
      expect(tree.ionic_voltage).to eq(4200)
    end

    it "returns 0 when latest_voltage_mv is nil" do
      tree = build(:tree, latest_voltage_mv: nil)
      expect(tree.ionic_voltage).to eq(0)
    end
  end

  describe "#under_threat?" do
    it "returns true when tree has unresolved alerts" do
      tree = create(:tree)
      create(:ews_alert, tree: tree, cluster: tree.cluster, status: :active, severity: :medium)

      expect(tree).to be_under_threat
    end

    it "returns false when tree has no alerts" do
      tree = create(:tree)
      expect(tree).not_to be_under_threat
    end

    it "returns false when all alerts are resolved" do
      tree = create(:tree)
      create(:ews_alert, tree: tree, cluster: tree.cluster, status: :resolved, severity: :medium)

      expect(tree).not_to be_under_threat
    end
  end

  describe "#current_stress" do
    it "returns 0.0 when no AI insights exist" do
      tree = create(:tree)
      expect(tree.current_stress).to eq(0.0)
    end

    it "returns stress_index from daily health summary" do
      tree = create(:tree)
      target = tree.cluster&.local_yesterday || (Time.current.utc.to_date - 1)
      create(:ai_insight, analyzable: tree, target_date: target, stress_index: 0.75)

      expect(tree.current_stress).to eq(0.75)
    end
  end

  describe "scopes" do
    describe ".active" do
      it "returns only active trees" do
        active = create(:tree, status: :active)
        dormant = create(:tree, status: :dormant)

        expect(described_class.active).to include(active)
        expect(described_class.active).not_to include(dormant)
      end
    end

    describe ".geolocated" do
      it "returns trees with both latitude and longitude" do
        located = create(:tree, latitude: 49.4, longitude: 32.0)
        unlocated = create(:tree, latitude: nil, longitude: nil)

        expect(described_class.geolocated).to include(located)
        expect(described_class.geolocated).not_to include(unlocated)
      end
    end

    describe ".silent" do
      it "returns trees not seen for more than 24 hours" do
        silent = create(:tree)
        silent.update_columns(last_seen_at: 25.hours.ago)

        recent = create(:tree)
        recent.update_columns(last_seen_at: 1.hour.ago)

        expect(described_class.silent).to include(silent)
        expect(described_class.silent).not_to include(recent)
      end
    end
  end

  # =========================================================================
  # FIRMWARE UPDATE STATUS (OTA Status Tracking)
  # =========================================================================
  describe "firmware_update_status" do
    it "defaults to fw_idle" do
      tree = build(:tree)
      expect(tree.firmware_update_status).to eq("fw_idle")
    end

    it "supports all OTA lifecycle states" do
      tree = build(:tree)
      %w[fw_idle fw_pending fw_downloading fw_verifying fw_flashing fw_failed fw_completed].each do |state|
        tree.firmware_update_status = state
        expect(tree.firmware_update_status).to eq(state)
      end
    end

    it "provides prefixed query methods" do
      tree = build(:tree, firmware_update_status: :fw_downloading)
      expect(tree).to be_firmware_fw_downloading
      expect(tree).not_to be_firmware_fw_idle
    end
  end

  describe "#latest_telemetry" do
    it "returns the most recent telemetry log" do
      tree = create(:tree)
      _old = create(:telemetry_log, tree: tree, created_at: 2.hours.ago)
      newest = create(:telemetry_log, tree: tree, created_at: 1.minute.ago)

      expect(tree.latest_telemetry).to eq(newest)
    end

    it "returns nil when no telemetry exists" do
      tree = create(:tree)
      expect(tree.latest_telemetry).to be_nil
    end

    it "memoizes the result" do
      tree = create(:tree)
      create(:telemetry_log, tree: tree)

      first_call = tree.latest_telemetry
      second_call = tree.latest_telemetry

      expect(first_call).to equal(second_call)
    end
  end

  describe "current_stress when cluster is nil" do
    it "falls back to UTC yesterday when cluster is nil" do
      tree = create(:tree)
      allow(tree).to receive(:cluster).and_return(nil)
      expect(tree.current_stress).to eq(0.0)
    end
  end

  describe "broadcast_map_update when latitude is nil" do
    it "returns nil without broadcasting when latitude is absent" do
      allow_any_instance_of(described_class).to receive(:broadcast_map_update).and_call_original
      tree = create(:tree)
      tree.update_columns(latitude: nil)
      tree.reload

      result = tree.broadcast_map_update
      expect(result).to be_nil
    end
  end

  describe "broadcast_map_update when longitude is nil" do
    it "returns nil without broadcasting when longitude is absent" do
      allow_any_instance_of(described_class).to receive(:broadcast_map_update).and_call_original
      tree = create(:tree)
      tree.update_columns(longitude: nil)
      tree.reload

      result = tree.broadcast_map_update
      expect(result).to be_nil
    end
  end

  describe "ensure_calibration when calibration already exists" do
    it "does not create a new calibration if one exists" do
      tree = create(:tree)
      existing_cal = tree.device_calibration
      expect(existing_cal).not_to be_nil

      tree.send(:ensure_calibration)
      expect(tree.device_calibration.id).to eq(existing_cal.id)
    end
  end

  describe "NormalizeIdentifier concern" do
    it "does not modify did when it is blank" do
      tree = described_class.new(did: "", cluster: create(:cluster), tree_family: create(:tree_family))
      expect(tree.did).to eq("")
    end

    it "strips and upcases when did is present" do
      tree = described_class.new(did: " snet-0000abcd ", cluster: create(:cluster), tree_family: create(:tree_family))
      expect(tree.did).to eq("SNET-0000ABCD")
    end
  end
end
