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
  let(:extracted_did) { did_hex.to_i(16).to_s(16).upcase }

  let!(:tree) do
    t = create(:tree)
    t.update_column(:did, extracted_did)
    t.reload
  end

  before do
    tree.create_device_calibration! if tree.device_calibration.nil?
    allow_any_instance_of(Wallet).to receive(:broadcast_balance_update)
    allow_any_instance_of(Tree).to receive(:broadcast_map_update)
    allow(AlertDispatchService).to receive(:analyze_and_trigger!)
    allow(SilkenNet::Attractor).to receive(:calculate_z).and_return(0.5)
    allow(IotexVerificationWorker).to receive(:perform_async)
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

    describe "when gateway is nil (queen_uid branch)" do
      it "processes chunks without gateway" do
        hex_did = tree.did.gsub("SNET-", "")

        chunk = build_chunk_with_params(did_hex: hex_did, voltage: 4200, temp: 22)
        service = TelemetryUnpackerService.new(chunk, nil)

        expect { service.perform }.not_to raise_error
      end
    end

    describe "interpret_status else branch" do
      it "handles unrecognized status codes gracefully" do
        service = TelemetryUnpackerService.new("", nil)
        result = service.send(:interpret_status, 0)
        expect(result).to eq(:homeostasis)

        result1 = service.send(:interpret_status, 1)
        expect(result1).to eq(:stress)

        result2 = service.send(:interpret_status, 2)
        expect(result2).to eq(:anomaly)

        result3 = service.send(:interpret_status, 3)
        expect(result3).to eq(:tamper_detected)
      end
    end

    describe "check_firmware_mismatch!" do
      let!(:active_firmware) { create(:bio_contract_firmware, :active, target_hardware_type: "Tree") }

      it "skips when reported_firmware_id is blank" do
        service = TelemetryUnpackerService.new("", nil)
        expect {
          service.send(:check_firmware_mismatch!, tree, nil)
        }.not_to raise_error
      end

      it "skips when latest firmware id is nil" do
        service = TelemetryUnpackerService.new("", nil)
        BioContractFirmware.update_all(is_active: false)

        expect {
          service.send(:check_firmware_mismatch!, tree, 999)
        }.not_to raise_error
      end

      it "skips when reported firmware matches latest" do
        service = TelemetryUnpackerService.new("", nil)
        expect {
          service.send(:check_firmware_mismatch!, tree, active_firmware.id)
        }.not_to raise_error
        expect(tree.reload.firmware_update_status).not_to eq("fw_pending")
      end

      it "marks tree as fw_pending when firmware mismatches and tree is fw_idle" do
        service = TelemetryUnpackerService.new("", nil)
        service.send(:check_firmware_mismatch!, tree, active_firmware.id + 999)

        expect(tree.reload.firmware_update_status).to eq("fw_pending")
      end

      it "does not mark tree as fw_pending when already fw_pending" do
        Tree.where(id: tree.id).update_all(firmware_update_status: :fw_pending)
        service = TelemetryUnpackerService.new("", nil)
        service.send(:check_firmware_mismatch!, tree, active_firmware.id + 999)

        expect(tree.reload.firmware_update_status).to eq("fw_pending")
      end
    end

    describe "latest_tree_firmware_id caching" do
      it "caches the result across calls" do
        create(:bio_contract_firmware, :active, target_hardware_type: "Tree")
        service = TelemetryUnpackerService.new("", nil)

        first_call = service.send(:latest_tree_firmware_id)
        second_call = service.send(:latest_tree_firmware_id)

        expect(first_call).to eq(second_call)
      end
    end

    describe "valid_sensor_data? range checks" do
      it "rejects out-of-range voltage" do
        service = TelemetryUnpackerService.new("", nil)
        data = [ 0, 6000, 22, 5, 120, 0, 5, "\x00\x00\x00\x00" ]
        expect(service.send(:valid_sensor_data?, data)).to be false
      end

      it "rejects out-of-range temperature" do
        service = TelemetryUnpackerService.new("", nil)
        data = [ 0, 4200, 100, 5, 120, 0, 5, "\x00\x00\x00\x00" ]
        expect(service.send(:valid_sensor_data?, data)).to be false
      end

      it "accepts valid sensor data" do
        service = TelemetryUnpackerService.new("", nil)
        data = [ 0, 4200, 22, 5, 120, 0, 5, "\x00\x00\x00\x00" ]
        expect(service.send(:valid_sensor_data?, data)).to be true
      end
    end
  end
end
