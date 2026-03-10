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
end
