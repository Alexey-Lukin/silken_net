# frozen_string_literal: true

require "rails_helper"
require "hil/queen_simulator"

RSpec.describe Hil::QueenSimulator do
  let(:gateway) { create(:gateway) }

  before do
    # Each gateway needs a HardwareKey for AES-CBC wire-mode encryption.
    create(:hardware_key, device_uid: gateway.uid, gateway: gateway)
    gateway.reload
  end

  describe "#initialize" do
    it "requires a gateway" do
      expect { described_class.new(nil) }.to raise_error(ArgumentError, /gateway is required/)
    end

    it "rejects unsupported modes" do
      expect { described_class.new(gateway, mode: :rest) }
        .to raise_error(ArgumentError, /unsupported mode/)
    end

    it "accepts :direct and :wire modes" do
      expect { described_class.new(gateway, mode: :direct) }.not_to raise_error
      expect { described_class.new(gateway, mode: :wire) }.not_to raise_error
    end
  end

  describe "#tick (direct mode)" do
    subject(:simulator) { described_class.new(gateway, mode: :direct, rng: Random.new(42)) }

    around do |example|
      Sidekiq::Testing.fake! { example.run }
    end

    before { GatewayTelemetryWorker.clear }

    it "enqueues GatewayTelemetryWorker for the gateway" do
      simulator.tick
      expect(GatewayTelemetryWorker.jobs.size).to eq(1)
      job = GatewayTelemetryWorker.jobs.first
      expect(job["args"].first).to eq(gateway.uid)
    end

    it "passes scenario-driven stats to the worker" do
      simulator.tick(scenario: :healthy)
      stats = GatewayTelemetryWorker.jobs.last["args"].last
      expect(stats["voltage_mv"]).to eq(4100)
      expect(stats["temperature_c"]).to eq(25)
      expect(stats["cellular_signal_csq"]).to eq(22)
      expect(stats["ip_address"]).to eq(gateway.ip_address)
    end

    it "honours per-call overrides" do
      simulator.tick(voltage_mv: 2950, temperature_c: 80, cellular_signal_csq: 1)
      stats = GatewayTelemetryWorker.jobs.last["args"].last
      expect(stats["voltage_mv"]).to eq(2950)
      expect(stats["temperature_c"]).to eq(80)
      expect(stats["cellular_signal_csq"]).to eq(1)
    end

    it "rejects unknown scenarios" do
      expect { simulator.tick(scenario: :armageddon) }
        .to raise_error(ArgumentError, /unknown scenario/)
    end

    it "returns the resolved stats with scenario metadata" do
      result = simulator.tick(scenario: :brownout)
      expect(result).to include(
        scenario: :brownout,
        voltage_mv: 3100,
        temperature_c: 22
      )
      expect(result[:uptime_s]).to be > 0
      expect(result[:cifo_fill]).to be_a(Integer)
    end

    it "advances uptime monotonically across ticks" do
      first  = simulator.tick
      second = simulator.tick
      expect(second[:uptime_s]).to be > first[:uptime_s]
    end

    describe ":cifo_filling scenario" do
      it "climbs toward the 50-slot capacity" do
        results = 30.times.map { simulator.tick(scenario: :cifo_filling) }
        max_fill = results.map { |s| s[:cifo_fill] }.max
        expect(max_fill).to be > 20
        expect(max_fill).to be <= 50
      end
    end
  end

  describe "#tick (wire mode)" do
    subject(:simulator) { described_class.new(gateway, mode: :wire, rng: Random.new(7)) }

    before do
      stub_const("CoapClient", Class.new do
        def self.put(url, payload, **)
          @calls ||= []
          @calls << { url: url, payload: payload }
          true
        end

        def self.calls
          @calls ||= []
        end
      end)
    end

    it "POSTs an encrypted 21-byte chunk to /telemetry/batch/<uid>" do
      simulator.tick(scenario: :healthy)
      call = CoapClient.calls.last
      expect(call[:url]).to eq("coap://127.0.0.1:5683/telemetry/batch/#{gateway.uid}")
      # IV (16 B) + 1 AES-CBC encrypted block of the 21-byte chunk
      # padded to 32 B = total 48 B.
      expect(call[:payload].bytesize).to eq(48)
    end

    it "produces a chunk that decrypts back into a sentinel inner payload" do
      simulator.tick(scenario: :brownout, voltage_mv: 3100)
      ciphertext = CoapClient.calls.last[:payload]
      iv = ciphertext[0, 16]
      body = ciphertext[16..]

      cipher = OpenSSL::Cipher.new("aes-256-cbc")
      cipher.decrypt
      cipher.key = gateway.hardware_key.binary_key
      cipher.iv  = iv
      cipher.padding = 0
      plain = cipher.update(body) + cipher.final

      # The first 21 bytes are the LoRa-shaped chunk.
      chunk = plain[0, 21]
      did = chunk.unpack1("N")
      rssi = chunk[4].unpack1("C")
      inner = chunk[5, 16].unpack("N n c C n C C a4")

      expect(did).to eq(0)        # Queen sentinel DID
      expect(rssi).to eq(0)       # local packet
      expect(inner[0]).to eq(0)   # inner DID slot zero too
      expect(inner[1]).to eq(3100) # Vcap → voltage_mv
      # Inner temperature_c sits at index 2 (int8, signed)
      expect(inner[2]).to eq(22)
    end
  end

  describe "#run!" do
    subject(:simulator) { described_class.new(gateway, mode: :direct, rng: Random.new(1)) }

    around do |example|
      Sidekiq::Testing.fake! { example.run }
    end

    before { GatewayTelemetryWorker.clear }

    it "emits N beacons" do
      results = simulator.run!(count: 7, interval: 0)
      expect(results.size).to eq(7)
      expect(GatewayTelemetryWorker.jobs.size).to eq(7)
    end

    it "applies the same scenario across the run" do
      simulator.run!(scenario: :overheat, count: 3, interval: 0)
      jobs = GatewayTelemetryWorker.jobs.last(3)
      jobs.each do |job|
        expect(job["args"].last["temperature_c"]).to eq(72)
      end
    end

    it "sleeps between ticks when interval is positive" do
      paced = described_class.new(gateway, mode: :direct, rng: Random.new(99))
      allow(paced).to receive(:sleep)
      paced.run!(count: 2, interval: 0.5)
      expect(paced).to have_received(:sleep).with(0.5).once
    end
  end
end
