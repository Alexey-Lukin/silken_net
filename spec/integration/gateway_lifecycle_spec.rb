# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Gateway lifecycle and telemetry relay" do
  let(:organization) { create(:organization) }
  let(:cluster) { create(:cluster, organization: organization) }

  before do
    allow_any_instance_of(Tree).to receive(:broadcast_map_update)
    allow_any_instance_of(Wallet).to receive(:broadcast_balance_update)
    allow(AlertNotificationWorker).to receive(:perform_async)
  end

  describe "Gateway state management" do
    let!(:gateway) { create(:gateway, cluster: cluster) }

    it "tracks online/offline status based on last_seen_at" do
      gateway.update!(last_seen_at: Time.current)
      expect(gateway.online?).to be true

      gateway.update!(last_seen_at: 2.hours.ago)
      expect(gateway.online?).to be false
    end

    it "mark_seen! updates last_seen_at and IP" do
      old_time = 1.hour.ago
      gateway.update_columns(last_seen_at: old_time)

      gateway.mark_seen!(new_ip: "10.0.0.1", voltage_mv: 4200)

      gateway.reload
      expect(gateway.last_seen_at).to be > old_time
      expect(gateway.ip_address).to eq("10.0.0.1")
      expect(gateway.latest_voltage_mv).to eq(4200)
    end

    it "calculates next wakeup time based on sleep interval" do
      now = Time.current
      gateway.update!(last_seen_at: now, config_sleep_interval_s: 300)
      expected = now + 300.seconds
      expect(gateway.next_wakeup_expected_at).to be_within(1.second).of(expected)
    end

    it "detects battery critical status" do
      gateway.update_columns(latest_voltage_mv: 3000)
      expect(gateway.battery_critical?).to be true

      gateway.update_columns(latest_voltage_mv: 4000)
      expect(gateway.battery_critical?).to be false
    end

    it "detects geolocated status" do
      gateway.update_columns(latitude: nil, longitude: nil)
      expect(gateway.geolocated?).to be false

      gateway.update_columns(latitude: 49.4, longitude: 32.0)
      expect(gateway.geolocated?).to be true
    end
  end

  describe "Gateway scopes" do
    it "online scope returns gateways seen recently" do
      online_gw = create(:gateway, cluster: cluster, last_seen_at: Time.current)
      _offline_gw = create(:gateway, cluster: cluster, last_seen_at: 2.hours.ago)

      expect(Gateway.online).to include(online_gw)
    end

    it "offline scope returns gateways not seen recently" do
      _online_gw = create(:gateway, cluster: cluster, last_seen_at: Time.current)
      offline_gw = create(:gateway, cluster: cluster, last_seen_at: 2.hours.ago)

      expect(Gateway.offline).to include(offline_gw)
    end
  end

  describe "HardwareKeyService provisioning and rotation" do
    let!(:gateway) { create(:gateway, cluster: cluster) }

    it "provisions a new hardware key for a gateway" do
      hex_key = HardwareKeyService.provision(gateway)

      expect(hex_key).to be_present
      expect(hex_key.length).to eq(64) # 32 bytes = 64 hex chars

      key_record = HardwareKey.find_by(device_uid: gateway.uid)
      expect(key_record).to be_present
      expect(key_record.aes_key_hex).to eq(hex_key)
    end

    it "rotates key with grace period protection" do
      allow(ActuatorCommandWorker).to receive(:perform_async)

      HardwareKeyService.provision(gateway)
      key_record = HardwareKey.find_by(device_uid: gateway.uid)
      old_key = key_record.aes_key_hex

      new_key = HardwareKeyService.rotate(gateway.uid)

      key_record.reload
      expect(key_record.aes_key_hex).to eq(new_key)
      expect(key_record.previous_aes_key_hex).to eq(old_key)
      expect(key_record.rotated_at).to be_present
    end

    it "prevents double rotation while grace period is active" do
      allow(ActuatorCommandWorker).to receive(:perform_async)

      HardwareKeyService.provision(gateway)
      HardwareKeyService.rotate(gateway.uid)

      expect { HardwareKeyService.rotate(gateway.uid) }
        .to raise_error(HardwareKeyService::RotationPendingError)
    end

    it "allows rotation after grace period is cleared" do
      allow(ActuatorCommandWorker).to receive(:perform_async)

      HardwareKeyService.provision(gateway)
      HardwareKeyService.rotate(gateway.uid)

      key_record = HardwareKey.find_by(device_uid: gateway.uid)
      key_record.clear_grace_period!

      expect { HardwareKeyService.rotate(gateway.uid) }.not_to raise_error
    end
  end

  describe "Gateway with trees (nested relationships)" do
    let!(:gateway) { create(:gateway, cluster: cluster) }
    let(:tree_family) { create(:tree_family) }

    it "accesses trees through cluster" do
      tree1 = create(:tree, cluster: cluster, tree_family: tree_family)
      tree2 = create(:tree, cluster: cluster, tree_family: tree_family)

      expect(gateway.trees.to_a).to include(tree1, tree2)
    end

    it "tracks telemetry logs through queen_uid" do
      tree = create(:tree, cluster: cluster, tree_family: tree_family)
      log = create(:telemetry_log, tree: tree, queen_uid: gateway.uid)

      expect(gateway.telemetry_logs).to include(log)
    end
  end
end
