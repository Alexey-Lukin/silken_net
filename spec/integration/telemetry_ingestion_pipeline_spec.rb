# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Telemetry ingestion pipeline end-to-end" do
  let(:organization) { create(:organization) }
  let(:cluster) { create(:cluster, organization: organization) }
  let(:tree_family) { create(:tree_family) }

  before do
    allow_any_instance_of(Tree).to receive(:broadcast_map_update)
    allow_any_instance_of(Wallet).to receive(:broadcast_balance_update)
    allow(AlertNotificationWorker).to receive(:perform_async)
    allow(EmergencyResponseService).to receive(:call)
  end

  describe "TelemetryUnpackerService processes binary batch" do
    let(:did_hex) { "0000ABCD" }
    let(:extracted_did) { did_hex.to_i(16).to_s(16).upcase }
    let!(:tree) do
      t = create(:tree, cluster: cluster, tree_family: tree_family)
      t.update_column(:did, extracted_did)
      t.reload
    end

    before do
      tree.create_device_calibration! if tree.device_calibration.nil?
      allow(AlertDispatchService).to receive(:analyze_and_trigger!)
      allow(SilkenNet::Attractor).to receive(:calculate_z).and_return(25.0)
    end

    # Helper: build a 21-byte telemetry chunk [DID:4][RSSI:1][Payload:16]
    # Payload uses PAYLOAD_FORMAT: "N n c C n C C a4"
    def build_chunk(did_hex, rssi, vcap_mv, temp_c, acoustic, metabolism, status_byte, ttl, pad = "\x00\x00\x00\x00")
      did_int = did_hex.to_i(16)
      header = [ did_int ].pack("N")
      rssi_byte = [ -rssi ].pack("C")
      payload = [ did_int, vcap_mv, temp_c, acoustic, metabolism, status_byte, ttl, pad ].pack("N n c C n C C a4")
      header + rssi_byte + payload
    end

    it "creates telemetry log, updates voltage, and credits wallet" do
      # status_byte: lower 6 bits = growth_points (10), upper 2 bits = bio_status (0 = homeostasis)
      chunk = build_chunk(did_hex, -70, 3800, 22, 5, 120, 10, 5)

      expect {
        TelemetryUnpackerService.call(chunk)
      }.to change(TelemetryLog, :count).by(1)

      log = TelemetryLog.last
      expect(log.tree).to eq(tree)
      expect(log.rssi).to eq(-70)
      expect(log.bio_status).to eq("homeostasis")
      expect(log.z_value).to be_present

      tree.reload
      expect(tree.last_seen_at).to be_present
      expect(tree.wallet.balance).to be > 0
    end

    it "rejects out-of-range sensor data (voltage > 5000 mV)" do
      chunk = build_chunk(did_hex, -70, 6000, 22, 5, 120, 0, 5)

      expect {
        TelemetryUnpackerService.call(chunk)
      }.not_to change(TelemetryLog, :count)
    end

    it "skips unknown DID gracefully" do
      chunk = build_chunk("FFFFFFFF", -70, 3800, 22, 5, 120, 0, 5)

      expect {
        TelemetryUnpackerService.call(chunk)
      }.not_to change(TelemetryLog, :count)
    end
  end

  describe "telemetry triggers alert dispatch" do
    let!(:tree) { create(:tree, cluster: cluster, tree_family: tree_family) }

    it "creates a fire alert when temperature exceeds threshold" do
      log = create(:telemetry_log, tree: tree, temperature_c: 70,
                                   bio_status: :homeostasis, voltage_mv: 3500,
                                   acoustic_events: 5, z_value: 25.0)

      expect { AlertDispatchService.analyze_and_trigger!(log) }
        .to change(EwsAlert, :count).by(1)

      alert = EwsAlert.last
      expect(alert.alert_type).to eq("fire_detected")
      expect(alert.severity).to eq("critical")
      expect(alert.tree).to eq(tree)
      expect(alert.cluster).to eq(cluster)
    end

    it "creates seismic alert for extreme acoustic events" do
      log = create(:telemetry_log, tree: tree, temperature_c: 20,
                                   bio_status: :homeostasis, voltage_mv: 3500,
                                   acoustic_events: 250, z_value: 25.0)

      expect { AlertDispatchService.analyze_and_trigger!(log) }
        .to change(EwsAlert, :count).by_at_least(1)

      expect(EwsAlert.last.alert_type).to eq("seismic_anomaly")
    end

    it "creates insect epidemic alert for moderate acoustic anomaly" do
      # acoustic_events > pest_limit but < 200 (seismic threshold)
      # Default pest_limit = 50 (no sap_flow_index set)
      log = create(:telemetry_log, tree: tree, temperature_c: 20,
                                   bio_status: :homeostasis, voltage_mv: 3500,
                                   acoustic_events: 100, z_value: 25.0)

      expect { AlertDispatchService.analyze_and_trigger!(log) }
        .to change(EwsAlert, :count).by(1)

      expect(EwsAlert.last.alert_type).to eq("insect_epidemic")
    end

    it "creates drought alert for out-of-homeostasis z_value" do
      log = create(:telemetry_log, tree: tree, temperature_c: 20,
                                   bio_status: :homeostasis, voltage_mv: 3500,
                                   acoustic_events: 5, z_value: 0.1) # below critical_z_min (5.0)

      expect { AlertDispatchService.analyze_and_trigger!(log) }
        .to change(EwsAlert, :count).by(1)

      expect(EwsAlert.last.alert_type).to eq("severe_drought")
    end

    it "respects silence filter — does not duplicate alerts within window" do
      log1 = create(:telemetry_log, tree: tree, temperature_c: 70,
                                    bio_status: :homeostasis, voltage_mv: 3500,
                                    acoustic_events: 5, z_value: 25.0)
      AlertDispatchService.analyze_and_trigger!(log1)
      expect(EwsAlert.count).to eq(1)

      log2 = create(:telemetry_log, tree: tree, temperature_c: 75,
                                    bio_status: :homeostasis, voltage_mv: 3500,
                                    acoustic_events: 5, z_value: 25.0)
      # Silence filter should prevent duplicate fire alert
      expect { AlertDispatchService.analyze_and_trigger!(log2) }
        .not_to change(EwsAlert, :count)
    end
  end

  describe "health streak tracking" do
    let!(:tree) { create(:tree, cluster: cluster, tree_family: tree_family) }

    it "increments health_streak for healthy telemetry" do
      expect(tree.health_streak).to eq(0)

      log = create(:telemetry_log, tree: tree, bio_status: :homeostasis,
                                   temperature_c: 22, acoustic_events: 5,
                                   voltage_mv: 4000, z_value: 25.0)

      service = TelemetryUnpackerService.new(nil, nil)
      service.send(:update_health_streak!, tree, log)

      expect(tree.health_streak).to eq(1)
    end

    it "resets health_streak for unhealthy telemetry" do
      Tree.where(id: tree.id).update_all(health_streak: 5)
      tree.health_streak = 5

      # Stressed log (temperature >= 50 or acoustic >= 20 makes it unhealthy)
      log = create(:telemetry_log, tree: tree, bio_status: :stress,
                                   temperature_c: 55, acoustic_events: 30,
                                   voltage_mv: 3500, z_value: 25.0)

      service = TelemetryUnpackerService.new(nil, nil)
      service.send(:update_health_streak!, tree, log)

      expect(tree.health_streak).to eq(0)
    end
  end
end
