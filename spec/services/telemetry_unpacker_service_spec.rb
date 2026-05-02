# frozen_string_literal: true

require "rails_helper"

RSpec.describe TelemetryUnpackerService, type: :service do
  # Builds a valid 21-byte binary chunk: [DID:4][RSSI:1][Payload:16]
  def build_chunk(did_hex, rssi, voltage, temp, acoustic, metabolism, status_byte, ttl)
    did_int = did_hex.to_i(16)
    header = [ did_int ].pack("N")
    rssi_byte = [ -rssi ].pack("C")
    payload = [ did_int, voltage, temp, acoustic, metabolism, status_byte, ttl, "\x00\x00\x00\x00" ].pack("N n c C n C C a4")
    header + rssi_byte + payload
  end

  let(:did_hex) { "0000ABCD" }
  let(:extracted_did) { format("SNET-%08X", did_hex.to_i(16)) }

  let!(:tree) { create(:tree, did: extracted_did) }

  before do
    tree.create_device_calibration! if tree.device_calibration.nil?
    allow_any_instance_of(Wallet).to receive(:broadcast_balance_update)
    allow_any_instance_of(Tree).to receive(:broadcast_map_update)
    allow(AlertDispatchService).to receive(:analyze_and_trigger!)
    allow(SilkenNet::Attractor).to receive(:calculate_z).and_return(0.5)
    allow(IotexVerificationWorker).to receive(:perform_async)
    allow(StreamrBroadcastWorker).to receive(:perform_async)
  end

  it "returns early when binary_batch is blank" do
    expect { described_class.call(nil) }.not_to change(TelemetryLog, :count)
    expect { described_class.call("") }.not_to change(TelemetryLog, :count)
  end

  it "unpacks a valid 21-byte chunk and creates a telemetry log" do
    chunk = build_chunk(did_hex, -70, 3500, 25, 5, 100, 0, 3)

    expect { described_class.call(chunk) }.to change(TelemetryLog, :count).by(1)

    log = TelemetryLog.last
    expect(log.tree).to eq(tree)
    expect(log.voltage_mv).to eq(3500)
    expect(log.temperature_c).to eq(25.0)
    expect(log.acoustic_events).to eq(5)
    expect(log.metabolism_s).to eq(100)
    expect(log.rssi).to eq(-70)
    expect(log.z_value).to eq(0.5)
    expect(log.mesh_ttl).to eq(3)
  end

  it "rejects sensor data outside safe voltage range" do
    chunk = build_chunk(did_hex, -70, 5001, 25, 5, 100, 0, 3)

    expect { described_class.call(chunk) }.not_to change(TelemetryLog, :count)
  end

  it "rejects sensor data outside safe temperature range" do
    chunk = build_chunk(did_hex, -70, 3500, 91, 5, 100, 0, 3)

    expect { described_class.call(chunk) }.not_to change(TelemetryLog, :count)
  end

  it "skips chunks shorter than 21 bytes" do
    chunk = build_chunk(did_hex, -70, 3500, 25, 5, 100, 0, 3)[0..19]

    expect { described_class.call(chunk) }.not_to change(TelemetryLog, :count)
  end

  it "skips unknown DIDs not found in registry" do
    chunk = build_chunk("FFFFFFFF", -70, 3500, 25, 5, 100, 0, 3)

    expect { described_class.call(chunk) }.not_to change(TelemetryLog, :count)
  end

  it "credits wallet with growth points" do
    status_byte = 10
    chunk = build_chunk(did_hex, -70, 3500, 25, 5, 100, status_byte, 3)

    expect { described_class.call(chunk) }.to change { tree.wallet.reload.balance }.by(10)
  end

  it "calls AlertDispatchService to analyze telemetry" do
    chunk = build_chunk(did_hex, -70, 3500, 25, 5, 100, 0, 3)

    described_class.call(chunk)

    expect(AlertDispatchService).to have_received(:analyze_and_trigger!).with(an_instance_of(TelemetryLog))
  end

  it "triggers IotexVerificationWorker after telemetry commit" do
    chunk = build_chunk(did_hex, -70, 3500, 25, 5, 100, 0, 3)

    described_class.call(chunk)

    expect(IotexVerificationWorker).to have_received(:perform_async).with(an_instance_of(Integer), an_instance_of(String))
  end

  it "triggers StreamrBroadcastWorker after telemetry commit" do
    chunk = build_chunk(did_hex, -70, 3500, 25, 5, 100, 0, 3)

    described_class.call(chunk)

    expect(StreamrBroadcastWorker).to have_received(:perform_async).with(an_instance_of(Integer), an_instance_of(String))
  end

  context "when transaction rolls back (P1-7 phantom job prevention)" do
    it "does not enqueue IotexVerificationWorker or StreamrBroadcastWorker" do
      chunk = build_chunk(did_hex, -70, 3500, 25, 5, 100, 0, 3)

      # Simulate a transaction rollback by making update_health_streak! raise.
      # Stub on Tree since that is where the atomic SQL runs; this triggers
      # ActiveRecord::Rollback inside the transaction, which is rescued by
      # process_chunk's broad rescue — the error is logged but not re-raised.
      allow(Tree).to receive(:where).and_call_original
      allow_any_instance_of(described_class).to receive(:update_health_streak!).and_raise(ActiveRecord::RecordInvalid)

      expect(Rails.logger).to receive(:error).with(/Telemetry Error/)
      expect { described_class.call(chunk) }.not_to raise_error

      # The key assertion: workers must NOT be enqueued when transaction rolls back
      expect(IotexVerificationWorker).not_to have_received(:perform_async)
      expect(StreamrBroadcastWorker).not_to have_received(:perform_async)
    end
  end

  describe "queen health routing" do
    let!(:gateway) { create(:gateway) }

    it "routes DID=0x00000000 packets to GatewayTelemetryWorker when gateway is present" do
      allow(GatewayTelemetryWorker).to receive(:perform_async)
      chunk = build_chunk("00000000", -70, 3500, 25, 5, 100, 0, 3)

      expect { described_class.call(chunk, gateway.id) }.not_to change(TelemetryLog, :count)
      expect(GatewayTelemetryWorker).to have_received(:perform_async).with(
        gateway.uid,
        a_hash_including(voltage_mv: anything, temperature_c: anything, cellular_signal_csq: anything)
      )
    end
  end

  describe "interpret_status" do
    it "maps status codes 1, 2, 3 to stress, anomaly, tamper_detected" do
      # Status byte upper 2 bits: code = status_byte >> 6
      # code 1 → :stress (status_byte = 0b01_000000 = 64)
      chunk_stress = build_chunk(did_hex, -70, 3500, 25, 5, 100, 64, 3)
      described_class.call(chunk_stress)
      log = TelemetryLog.last
      expect(log.bio_status).to eq("stress")

      # code 2 → :anomaly (status_byte = 0b10_000000 = 128)
      chunk_anomaly = build_chunk(did_hex, -70, 3500, 25, 5, 100, 128, 3)
      described_class.call(chunk_anomaly)
      log = TelemetryLog.last
      expect(log.bio_status).to eq("anomaly")

      # code 3 → :tamper_detected (status_byte = 0b11_000000 = 192)
      chunk_tamper = build_chunk(did_hex, -70, 3500, 25, 5, 100, 192, 3)
      described_class.call(chunk_tamper)
      log = TelemetryLog.last
      expect(log.bio_status).to eq("tamper_detected")
    end
  end

  describe "error handling" do
    it "logs error and continues when process_chunk raises" do
      allow(SilkenNet::Attractor).to receive(:calculate_z).and_raise(StandardError.new("test error"))

      chunk = build_chunk(did_hex, -70, 3500, 25, 5, 100, 0, 3)

      expect(Rails.logger).to receive(:error).with(/Telemetry Error/)
      expect { described_class.call(chunk) }.not_to raise_error
    end
  end

  describe "edge cases from coverage enhancement" do
    let(:organization) { create(:organization) }
    let(:cluster) { create(:cluster, organization: organization) }
    let(:gateway) { create(:gateway, :online, cluster: cluster) }

    # Keyword-argument variant of build_chunk for coverage enhancement tests
    def build_chunk_with_params(did_hex:, rssi: 65, voltage: 4200, temp: 22, acoustic: 5, metabolism: 120, status_byte: 0, ttl: 5, firmware_id: 0)
      did_int = did_hex.to_i(16)
      did_bytes = [ did_int ].pack("N")
      rssi_byte = [ rssi ].pack("C")

      growth_points = status_byte & 0x3F
      combined_status = (status_byte << 6) | growth_points
      pad = [ firmware_id ].pack("n") + "\x00\x00"

      payload = [ did_int, voltage, temp, acoustic, metabolism, combined_status, ttl ].pack("N n c C n C C") + pad
      did_bytes + rssi_byte + payload
    end

    before do
      allow(GatewayTelemetryWorker).to receive(:perform_async)
    end

    describe "queen_uid branch" do
      it "processes chunks without gateway" do
        hex_did = tree.did.gsub("SNET-", "")

        chunk = build_chunk_with_params(did_hex: hex_did, voltage: 4200, temp: 22)
        service = described_class.new(chunk, nil)

        expect { service.perform }.not_to raise_error
      end

      it "sets queen_uid from gateway when gateway is present" do
        tree_r2 = create(:tree, did: format("SNET-%08X", "0000AB01".to_i(16)), cluster: cluster)
        tree_r2.create_device_calibration! if tree_r2.device_calibration.nil?

        did_int = "0000AB01".to_i(16)
        did_bytes = [ did_int ].pack("N")
        rssi_byte = [ 65 ].pack("C")
        pad = [ 0 ].pack("n") + "\x00\x00"
        payload = [ did_int, 3800, 22, 0, 100, 0x05, 3, pad ].pack("N n c C n C C a4")
        chunk = did_bytes + rssi_byte + payload

        service = described_class.new(chunk, gateway.id)
        service.perform

        log = tree_r2.telemetry_logs.last
        expect(log).not_to be_nil
        expect(log.queen_uid).to eq(gateway.uid)
      end
    end

    describe "interpret_status else branch" do
      it "handles unrecognized status codes gracefully" do
        service = described_class.new("", nil)
        result = service.send(:interpret_status, 0)
        expect(result).to eq(:homeostasis)

        result1 = service.send(:interpret_status, 1)
        expect(result1).to eq(:stress)

        result2 = service.send(:interpret_status, 2)
        expect(result2).to eq(:anomaly)

        result3 = service.send(:interpret_status, 3)
        expect(result3).to eq(:tamper_detected)
      end

      it "returns nil for an undefined status code" do
        service = described_class.new("", nil)
        result = service.send(:interpret_status, 99)
        expect(result).to be_nil
      end
    end

    describe "check_firmware_mismatch!" do
      let!(:active_firmware) { create(:bio_contract_firmware, :active, target_hardware_type: "Tree") }

      it "skips when reported_firmware_id is blank" do
        service = described_class.new("", nil)
        expect {
          service.send(:check_firmware_mismatch!, tree, nil)
        }.not_to raise_error
      end

      it "skips when latest firmware id is nil" do
        service = described_class.new("", nil)
        BioContractFirmware.update_all(is_active: false)

        expect {
          service.send(:check_firmware_mismatch!, tree, 999)
        }.not_to raise_error
      end

      it "skips when reported firmware matches latest" do
        service = described_class.new("", nil)
        expect {
          service.send(:check_firmware_mismatch!, tree, active_firmware.id)
        }.not_to raise_error
        expect(tree.reload.firmware_update_status).not_to eq("fw_pending")
      end

      it "marks tree as fw_pending when firmware mismatches and tree is fw_idle" do
        service = described_class.new("", nil)
        service.send(:check_firmware_mismatch!, tree, active_firmware.id + 999)

        expect(tree.reload.firmware_update_status).to eq("fw_pending")
      end

      it "does not mark tree as fw_pending when already fw_pending" do
        Tree.where(id: tree.id).update_all(firmware_update_status: :fw_pending)
        service = described_class.new("", nil)
        service.send(:check_firmware_mismatch!, tree, active_firmware.id + 999)

        expect(tree.reload.firmware_update_status).to eq("fw_pending")
      end
    end

    describe "firmware_version_id assignment" do
      it "sets firmware_version_id when firmware_id is positive" do
        tree_r2 = create(:tree, did: format("SNET-%08X", "0000AB01".to_i(16)), cluster: cluster)
        tree_r2.create_device_calibration! if tree_r2.device_calibration.nil?

        did_int = "0000AB01".to_i(16)
        did_bytes = [ did_int ].pack("N")
        rssi_byte = [ 65 ].pack("C")
        pad = [ 42 ].pack("n") + "\x00\x00"
        payload = [ did_int, 3800, 22, 0, 100, 0x05, 3, pad ].pack("N n c C n C C a4")
        chunk = did_bytes + rssi_byte + payload

        service = described_class.new(chunk, gateway.id)
        service.perform

        log = tree_r2.telemetry_logs.last
        expect(log.firmware_version_id).to eq(42)
      end

      it "sets firmware_version_id to nil when firmware_id is zero" do
        tree_r2 = create(:tree, did: format("SNET-%08X", "0000AB01".to_i(16)), cluster: cluster)
        tree_r2.create_device_calibration! if tree_r2.device_calibration.nil?

        did_int = "0000AB01".to_i(16)
        did_bytes = [ did_int ].pack("N")
        rssi_byte = [ 65 ].pack("C")
        pad = [ 0 ].pack("n") + "\x00\x00"
        payload = [ did_int, 3800, 22, 0, 100, 0x05, 3, pad ].pack("N n c C n C C a4")
        chunk = did_bytes + rssi_byte + payload

        service = described_class.new(chunk, gateway.id)
        service.perform

        log = tree_r2.telemetry_logs.last
        expect(log.firmware_version_id).to be_nil
      end
    end

    describe "latest_tree_firmware_id caching" do
      it "caches the result across calls" do
        create(:bio_contract_firmware, :active, target_hardware_type: "Tree")
        service = described_class.new("", nil)

        first_call = service.send(:latest_tree_firmware_id)
        second_call = service.send(:latest_tree_firmware_id)

        expect(first_call).to eq(second_call)
      end
    end

    describe "valid_sensor_data? range checks" do
      it "rejects out-of-range voltage" do
        service = described_class.new("", nil)
        data = [ 0, 6000, 22, 5, 120, 0, 5, "\x00\x00\x00\x00" ]
        expect(service.send(:valid_sensor_data?, data)).to be false
      end

      it "rejects out-of-range temperature" do
        service = described_class.new("", nil)
        data = [ 0, 4200, 100, 5, 120, 0, 5, "\x00\x00\x00\x00" ]
        expect(service.send(:valid_sensor_data?, data)).to be false
      end

      it "accepts valid sensor data" do
        service = described_class.new("", nil)
        data = [ 0, 4200, 22, 5, 120, 0, 5, "\x00\x00\x00\x00" ]
        expect(service.send(:valid_sensor_data?, data)).to be true
      end

      it "accepts voltage at lower boundary (0 mV)" do
        service = described_class.new("", nil)
        data = [ 0, 0, 22, 5, 120, 0, 5, "\x00\x00\x00\x00" ]
        expect(service.send(:valid_sensor_data?, data)).to be true
      end

      it "accepts voltage at upper boundary (5000 mV)" do
        service = described_class.new("", nil)
        data = [ 0, 5000, 22, 5, 120, 0, 5, "\x00\x00\x00\x00" ]
        expect(service.send(:valid_sensor_data?, data)).to be true
      end

      it "rejects voltage just above upper boundary (5001 mV)" do
        service = described_class.new("", nil)
        data = [ 0, 5001, 22, 5, 120, 0, 5, "\x00\x00\x00\x00" ]
        expect(service.send(:valid_sensor_data?, data)).to be false
      end

      it "accepts temperature at lower boundary (-45°C)" do
        service = described_class.new("", nil)
        data = [ 0, 3500, -45, 5, 120, 0, 5, "\x00\x00\x00\x00" ]
        expect(service.send(:valid_sensor_data?, data)).to be true
      end

      it "accepts temperature at upper boundary (90°C)" do
        service = described_class.new("", nil)
        data = [ 0, 3500, 90, 5, 120, 0, 5, "\x00\x00\x00\x00" ]
        expect(service.send(:valid_sensor_data?, data)).to be true
      end

      it "rejects temperature just above upper boundary (91°C)" do
        service = described_class.new("", nil)
        data = [ 0, 3500, 91, 5, 120, 0, 5, "\x00\x00\x00\x00" ]
        expect(service.send(:valid_sensor_data?, data)).to be false
      end

      it "rejects temperature just below lower boundary (-46°C)" do
        service = described_class.new("", nil)
        data = [ 0, 3500, -46, 5, 120, 0, 5, "\x00\x00\x00\x00" ]
        expect(service.send(:valid_sensor_data?, data)).to be false
      end
    end

    describe "check_z_divergence!" do
      let!(:tree_family) { create(:tree_family) }
      let!(:tree_with_family) do
        t = create(:tree, did: format("SNET-%08X", "0000AC01".to_i(16)), cluster: cluster, tree_family: tree_family)
        t.create_device_calibration! if t.device_calibration.nil?
        t
      end

      it "[FW.8] uses global defaults when tree_family is nil (governance fallback)" do
        tree_no_family = create(:tree, did: format("SNET-%08X", "0000AC02".to_i(16)), cluster: cluster, tree_family: tree_family)
        # Simulate nil tree_family by stubbing the association
        allow(tree_no_family).to receive(:tree_family).and_return(nil)
        service = described_class.new("", nil)
        # z=50 is ABOVE global default Tree::GLOBAL_LORENZ_Z_MAX (45.0)
        # device says "homeostasis" → divergence MUST be detected (server_healthy=false)
        attributes = { z_value: 50.0, bio_status: :homeostasis }

        expect(SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL).to receive(:increment)
        service.send(:check_z_divergence!, tree_no_family, attributes)
      end

      it "[FW.8] no divergence when z_value is within global defaults and family is nil" do
        tree_no_family = create(:tree, did: format("SNET-%08X", "0000AC03".to_i(16)), cluster: cluster, tree_family: tree_family)
        allow(tree_no_family).to receive(:tree_family).and_return(nil)
        service = described_class.new("", nil)
        attributes = { z_value: 25.0, bio_status: :homeostasis } # well within 2..45

        expect(SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL).not_to receive(:increment)
        service.send(:check_z_divergence!, tree_no_family, attributes)
      end

      it "skips when server_z is nil" do
        service = described_class.new("", nil)
        attributes = { z_value: nil, bio_status: :homeostasis }

        expect(SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL).not_to receive(:increment)
        service.send(:check_z_divergence!, tree_with_family, attributes)
      end

      it "skips when device_bio_status is nil" do
        service = described_class.new("", nil)
        attributes = { z_value: 25.0, bio_status: nil }

        expect(SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL).not_to receive(:increment)
        service.send(:check_z_divergence!, tree_with_family, attributes)
      end

      it "increments fraud metric when device says homeostasis but server Z is unhealthy" do
        service = described_class.new("", nil)
        allow_any_instance_of(TreeFamily).to receive(:healthy_z?).and_return(false)
        attributes = { z_value: 50.0, bio_status: :homeostasis }

        expect(SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL).to receive(:increment)
        service.send(:check_z_divergence!, tree_with_family, attributes)
      end

      it "does not flag when both device and server agree on healthy" do
        service = described_class.new("", nil)
        allow_any_instance_of(TreeFamily).to receive(:healthy_z?).and_return(true)
        attributes = { z_value: 25.0, bio_status: :homeostasis }

        expect(SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL).not_to receive(:increment)
        service.send(:check_z_divergence!, tree_with_family, attributes)
      end

      it "does not flag when both device and server agree on unhealthy" do
        service = described_class.new("", nil)
        allow_any_instance_of(TreeFamily).to receive(:healthy_z?).and_return(false)
        attributes = { z_value: 50.0, bio_status: :stress }

        expect(SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL).not_to receive(:increment)
        service.send(:check_z_divergence!, tree_with_family, attributes)
      end
    end

    describe "update_health_streak!" do
      it "increments health_streak when log is healthy" do
        tree.update_column(:health_streak, 5)
        tree.reload
        log = create(:telemetry_log, tree: tree, bio_status: :homeostasis)
        allow(log).to receive(:healthy?).and_return(true)

        service = described_class.new("", nil)
        service.send(:update_health_streak!, tree, log)

        expect(tree.reload.health_streak).to eq(6)
      end

      it "resets health_streak to 0 when log is unhealthy" do
        tree.update_column(:health_streak, 10)
        tree.reload
        log = create(:telemetry_log, tree: tree, bio_status: :stress)
        allow(log).to receive(:healthy?).and_return(false)

        service = described_class.new("", nil)
        service.send(:update_health_streak!, tree, log)

        expect(tree.reload.health_streak).to eq(0)
      end

      it "syncs in-memory tree state after SQL update" do
        tree.update_column(:health_streak, 3)
        tree.reload
        log = create(:telemetry_log, tree: tree, bio_status: :homeostasis)
        allow(log).to receive(:healthy?).and_return(true)

        service = described_class.new("", nil)
        service.send(:update_health_streak!, tree, log)

        # Verify in-memory state was updated (without reload)
        expect(tree.health_streak).to eq(4)
      end
    end

    describe "acoustic_events overflow warning" do
      it "logs warning when acoustic_events is 255 (saturated)" do
        chunk = build_chunk(did_hex, -70, 3500, 25, 255, 100, 0, 3)

        allow(Rails.logger).to receive(:warn).and_call_original
        expect(Rails.logger).to receive(:warn).with(/Acoustic Overflow/).once

        described_class.call(chunk)
      end

      it "does not log warning for acoustic_events below 255" do
        chunk = build_chunk(did_hex, -70, 3500, 25, 254, 100, 0, 3)

        allow(Rails.logger).to receive(:warn).and_call_original
        expect(Rails.logger).not_to receive(:warn).with(/Acoustic Overflow/)

        described_class.call(chunk)
      end
    end

    describe "multiple chunks in batch" do
      let(:did_hex2) { "0000ABCE" }
      let(:extracted_did2) { format("SNET-%08X", did_hex2.to_i(16)) }
      let!(:tree2) do
        t = create(:tree, did: extracted_did2)
        t.create_device_calibration! if t.device_calibration.nil?
        t
      end

      it "processes multiple valid chunks in a single batch" do
        chunk1 = build_chunk(did_hex, -70, 3500, 25, 5, 100, 0, 3)
        chunk2 = build_chunk(did_hex2, -80, 4000, 20, 3, 150, 0, 3)
        batch = chunk1 + chunk2

        expect { described_class.call(batch) }.to change(TelemetryLog, :count).by(2)
      end

      it "skips invalid chunks while processing valid ones" do
        valid_chunk = build_chunk(did_hex, -70, 3500, 25, 5, 100, 0, 3)
        invalid_chunk = build_chunk("FFFFFFFF", -70, 3500, 25, 5, 100, 0, 3) # unknown DID
        batch = valid_chunk + invalid_chunk

        expect { described_class.call(batch) }.to change(TelemetryLog, :count).by(1)
      end
    end

    describe "RSSI inversion" do
      it "correctly inverts RSSI from unsigned to negative" do
        # RSSI -70 → stored as 70 (unsigned) in packet → read back as -70
        chunk = build_chunk(did_hex, -70, 3500, 25, 5, 100, 0, 3)

        described_class.call(chunk)
        log = TelemetryLog.last
        expect(log.rssi).to eq(-70)
      end

      it "correctly handles RSSI -128 (worst signal)" do
        chunk = build_chunk(did_hex, -128, 3500, 25, 5, 100, 0, 3)

        described_class.call(chunk)
        log = TelemetryLog.last
        expect(log.rssi).to eq(-128)
      end
    end

    describe "growth_points extraction from status_byte" do
      it "extracts growth_points from lower 6 bits" do
        # status_byte = 0b00_101010 = 42 → bio_status=homeostasis(0), growth_points=42
        chunk = build_chunk(did_hex, -70, 3500, 25, 5, 100, 42, 3)

        described_class.call(chunk)
        log = TelemetryLog.last
        expect(log.growth_points).to eq(42)
        expect(log.bio_status).to eq("homeostasis")
      end

      it "extracts max growth_points (63) correctly" do
        # status_byte = 0b00_111111 = 63
        chunk = build_chunk(did_hex, -70, 3500, 25, 5, 100, 63, 3)

        described_class.call(chunk)
        log = TelemetryLog.last
        expect(log.growth_points).to eq(63)
      end

      it "extracts both status and growth_points from combined byte" do
        # status_byte = 0b01_001010 = 74 → bio_status=stress(1), growth_points=10
        chunk = build_chunk(did_hex, -70, 3500, 25, 5, 100, 74, 3)

        described_class.call(chunk)
        log = TelemetryLog.last
        expect(log.growth_points).to eq(10)
        expect(log.bio_status).to eq("stress")
      end
    end
  end
end
