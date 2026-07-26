# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"
require "hil/queen_simulator"

# [ARCH.54] Симулятор пульсу Королеви (v2): :direct = stats-hash напряму,
# :wire = підписаний empty-flush heartbeat (QATT-v2, health у header'і).
# Unsigned wire health у протоколі не існує — wire-режим мінтить Ed25519
# eagerly, як фабричний provisioning.
RSpec.describe Hil::QueenSimulator do
  let(:gateway) { create(:gateway) }

  before do
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

    it "wire-mode eagerly registers the attestation pubkey on the HardwareKey" do
      expect {
        described_class.new(gateway, mode: :wire, rng: Random.new(1))
      }.to change { gateway.hardware_key.reload.ed25519_public_key_hex }.from(nil)
    end

    it "derives a deterministic keypair from the injected rng" do
      described_class.new(gateway, mode: :wire, rng: Random.new(99))
      first = gateway.hardware_key.reload.ed25519_public_key_hex

      gateway.hardware_key.update!(ed25519_public_key_hex: nil)
      described_class.new(gateway, mode: :wire, rng: Random.new(99))

      expect(gateway.hardware_key.reload.ed25519_public_key_hex).to eq(first)
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

    it "passes scenario-driven pulse stats to the worker" do
      simulator.tick(scenario: :healthy)
      stats = GatewayTelemetryWorker.jobs.last["args"].last
      expect(stats["cellular_signal_csq"]).to eq(22)
      expect(stats["lora_rx_drops"]).to eq(0)
      expect(stats["coap_fail_count"]).to eq(0)
      expect(stats["uptime_min"]).to be > 0
      expect(stats["ip_address"]).to eq(gateway.ip_address)
    end

    it "honours per-call overrides" do
      simulator.tick(cellular_signal_csq: 1, coap_fail_count: 12, lora_rx_drops: 200)
      stats = GatewayTelemetryWorker.jobs.last["args"].last
      expect(stats["cellular_signal_csq"]).to eq(1)
      expect(stats["coap_fail_count"]).to eq(12)
      expect(stats["lora_rx_drops"]).to eq(200)
    end

    it ":no_signal scenario carries nil csq (сентинель 0xFF на дроті)" do
      simulator.tick(scenario: :no_signal)
      stats = GatewayTelemetryWorker.jobs.last["args"].last
      expect(stats["cellular_signal_csq"]).to be_nil
    end

    it "rejects unknown scenarios" do
      expect { simulator.tick(scenario: :armageddon) }
        .to raise_error(ArgumentError, /unknown scenario/)
    end

    it "returns the resolved stats with scenario metadata" do
      result = simulator.tick(scenario: :uplink_degraded)
      expect(result).to include(
        "scenario" => :uplink_degraded,
        "coap_fail_count" => 12
      )
      expect(result["uptime_min"]).to be > 0
      expect(result["cifo_fill"]).to be_a(Integer)
    end

    it "advances uptime monotonically across ticks" do
      first  = simulator.tick
      second = simulator.tick
      expect(second["uptime_min"]).to be > first["uptime_min"]
    end

    describe ":cifo_filling scenario" do
      it "climbs toward the 50-slot capacity" do
        results = 30.times.map { simulator.tick(scenario: :cifo_filling) }
        max_fill = results.map { |s| s["cifo_fill"] }.max
        expect(max_fill).to be > 20
        expect(max_fill).to be <= 50
      end
    end
  end

  describe "#tick (wire mode — signed v2 heartbeat)" do
    # let, not subject: tests below stub methods on it directly
    # (RSpec/SubjectStub) — it's a plain collaborator, never used via is_expected.
    let(:simulator) { described_class.new(gateway, mode: :wire, rng: Random.new(7)) }

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

    it "POSTs the empty-flush heartbeat envelope to /telemetry/batch/<uid>" do
      simulator.tick(scenario: :healthy)
      call = CoapClient.calls.last
      expect(call[:url]).to eq("coap://127.0.0.1:5683/telemetry/batch/#{gateway.uid}")
      # header 17 + IV 16 + ct 0 + sig 64 = 97 B
      expect(call[:payload].bytesize).to eq(97)
    end

    it "emits an envelope with the signed-vs-legacy residue (≡ 1 mod 16)" do
      simulator.tick(scenario: :healthy)
      payload = CoapClient.calls.last[:payload]
      expect(payload.bytesize % 16).to eq(UnpackTelemetryWorker::QATT_RESIDUE)
      expect(payload.getbyte(0)).to eq(described_class::QATT_VERSION_2)
    end

    it "signature verifies against the registered pubkey (v2 domain tag)" do
      simulator.tick(scenario: :healthy)
      payload = CoapClient.calls.last[:payload]

      sig  = payload.byteslice(-64, 64)
      body = payload.byteslice(0, payload.bytesize - 64)
      uid  = gateway.uid
      message = described_class::QATT_DOMAIN_TAG + [ uid.bytesize ].pack("C") + uid.b + body

      expect(
        Ed25519Crypto::SigningService.verify(
          gateway.hardware_key.reload.ed25519_public_key_hex,
          sig.unpack1("H*"), message
        )
      ).to be(true)
    end

    it "packs the pulse into the signed header (byte-parity with tick stats)" do
      stats = simulator.tick(scenario: :uplink_degraded, uptime_min: 5310, cifo_fill: 42)
      payload = CoapClient.calls.last[:payload]

      up = (payload.getbyte(9) << 16) | (payload.getbyte(10) << 8) | payload.getbyte(11)
      expect(up).to eq(5310)
      expect(payload.getbyte(12)).to eq(42)                       # cifo_fill
      expect(payload.getbyte(13)).to eq(stats["lora_rx_drops"])   # 4
      expect(payload.getbyte(14)).to eq(stats["coap_fail_count"]) # 12
      expect(payload.getbyte(15)).to eq(18)                       # csq
    end

    it "nil csq rides as the 0xFF wire sentinel" do
      simulator.tick(scenario: :no_signal)
      payload = CoapClient.calls.last[:payload]
      expect(payload.getbyte(15)).to eq(described_class::QATT_CSQ_NOT_READ)
    end

    it "increments flush_seq once per dispatched envelope" do
      simulator.tick
      simulator.tick
      seqs = CoapClient.calls.map { |c| c[:payload].byteslice(5, 4).unpack1("N") }
      expect(seqs).to eq([ 1, 2 ])
    end

    it "lazily requires coap_client when the constant isn't already loaded" do
      # The `before` above stub_const's CoapClient for every other example in
      # this block; hide it here so dispatch_wire's `unless defined?(CoapClient)`
      # sees a cold process and takes the require branch for real.
      hide_const("CoapClient")
      allow(simulator).to receive(:require).with("coap_client") {
        stub_const("CoapClient", Class.new { def self.put(*, **) = true })
      }

      expect { simulator.tick(scenario: :healthy) }.not_to raise_error
      expect(simulator).to have_received(:require).with("coap_client")
    end
  end

  describe "#run!" do
    # let, not subject: the sleep-stub test below stubs a method on it
    # directly (RSpec/SubjectStub) — plain collaborator, never is_expected.
    let(:simulator) { described_class.new(gateway, mode: :direct, rng: Random.new(3)) }

    around do |example|
      Sidekiq::Testing.fake! { example.run }
    end

    before { GatewayTelemetryWorker.clear }

    it "emits `count` pulses and returns their stats" do
      results = simulator.run!(scenario: :healthy, count: 4)
      expect(results.size).to eq(4)
      expect(GatewayTelemetryWorker.jobs.size).to eq(4)
    end

    it "applies the same scenario across the run" do
      results = simulator.run!(scenario: :uplink_degraded, count: 3)
      expect(results.map { |s| s["coap_fail_count"] }.uniq).to eq([ 12 ])
    end

    it "sleeps between ticks when interval is positive, skipping the first tick" do
      allow(simulator).to receive(:sleep)

      simulator.run!(scenario: :healthy, count: 3, interval: 0.01)

      expect(simulator).to have_received(:sleep).with(0.01).exactly(2).times
    end
  end
end
