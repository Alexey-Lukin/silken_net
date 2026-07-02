# frozen_string_literal: true

require "rails_helper"
require "hil/queen_simulator"

# [L1 QATT × HIL] End-to-end: the signed envelope built by the Queen HIL
# digital twin passes the REAL UnpackTelemetryWorker verification chain all
# the way to the DB markers — the "e2e without silicon" rung of the
# trust-origin ladder (docs/05_02; wire home docs/03_05 §2.2). The envelope
# builder (simulator) and the verifier (worker) are independent
# implementations — this spec is their meeting point.
RSpec.describe "QATT HIL end-to-end" do
  let(:gateway) { create(:gateway, ip_address: "10.7.0.1") }
  # Fresh keypair per example (simulator mints it eagerly) → fresh signature
  # → fresh anti-replay nonce; no Redis cleanup needed between runs.
  let(:simulator) { Hil::QueenSimulator.new(gateway, mode: :wire, signed: true) }

  around do |example|
    Sidekiq::Testing.fake! { example.run }
  end

  before do
    create(:hardware_key, device_uid: gateway.uid, gateway: gateway)
    gateway.reload
    GatewayTelemetryWorker.clear

    stub_const("CoapClient", Class.new do
      def self.put(url, payload, **)
        @calls ||= []
        @calls << { url: url, payload: payload.dup }
        true
      end

      def self.calls
        @calls ||= []
      end
    end)

    allow(Turbo::StreamsChannel).to receive(:broadcast_prepend_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_remove_to)
    allow(ActionCable.server).to receive(:broadcast)
  end

  # The worker is fed byte-for-byte what the CoAP listener enqueues
  # (lib/daemons/coap_listener): Base64 payload + sender IP + UID parsed
  # from the intercepted URI path — honouring the contract that the UID
  # rides both the URL and the signed message.
  def intercepted
    call = CoapClient.calls.last
    { encoded: Base64.strict_encode64(call[:payload]),
      uid: call[:url].split("/").last,
      raw: call[:payload] }
  end

  it "attests a simulator-signed batch end-to-end down to the DB markers" do
    simulator.tick(scenario: :healthy)
    package = intercepted

    expect(TelemetryUnpackerService).to receive(:call)
      .with(anything, gateway.id, gateway_attested: true).and_call_original

    UnpackTelemetryWorker.new.perform(package[:encoded], gateway.ip_address, package[:uid])

    expect(gateway.reload.last_attested_at).to be_present
    # The REAL unpacker ran: the DID=0 sentinel chunk reached route_queen_health.
    expect(GatewayTelemetryWorker.jobs.size).to eq(1)
  end

  it "rejects a tampered ciphertext with the bad-signature metric" do
    simulator.tick(scenario: :healthy)
    package = intercepted
    tampered = package[:raw].dup
    tampered.setbyte(30, tampered.getbyte(30) ^ 0x01) # inside IV/ct, past the 9-byte header
    allow(SilkenNet::Metrics::COAP_PACKETS_RECEIVED_TOTAL).to receive(:increment)

    expect(TelemetryUnpackerService).not_to receive(:call)
    UnpackTelemetryWorker.new.perform(Base64.strict_encode64(tampered), gateway.ip_address, package[:uid])

    expect(gateway.reload.last_attested_at).to be_nil
    expect(SilkenNet::Metrics::COAP_PACKETS_RECEIVED_TOTAL)
      .to have_received(:increment).with(labels: { status: "attest_bad_signature" })
  end

  it "rejects a replay of the same envelope via the nonce (first pass attests)" do
    simulator.tick(scenario: :healthy)
    package = intercepted
    allow(SilkenNet::Metrics::COAP_PACKETS_RECEIVED_TOTAL).to receive(:increment)
    allow(TelemetryUnpackerService).to receive(:call).and_call_original

    UnpackTelemetryWorker.new.perform(package[:encoded], gateway.ip_address, package[:uid])
    expect(gateway.reload.last_attested_at).to be_present
    expect(TelemetryUnpackerService).to have_received(:call).once

    UnpackTelemetryWorker.new.perform(package[:encoded], gateway.ip_address, package[:uid])

    expect(TelemetryUnpackerService).to have_received(:call).once
    expect(SilkenNet::Metrics::COAP_PACKETS_RECEIVED_TOTAL)
      .to have_received(:increment).with(labels: { status: "attest_replay" })
  end

  it "downgrades to L0 (:unverified) when the registered pubkey is wiped — provisioning gap" do
    simulator.tick(scenario: :healthy)
    package = intercepted
    gateway.hardware_key.update!(ed25519_public_key_hex: nil)

    expect(TelemetryUnpackerService).to receive(:call)
      .with(anything, gateway.id, gateway_attested: false).and_call_original

    UnpackTelemetryWorker.new.perform(package[:encoded], gateway.ip_address, package[:uid])

    expect(gateway.reload.last_attested_at).to be_nil
  end

  it "recovers an attested batch after a mid-unpack crash — Sidekiq retry with the same jid resumes" do
    simulator.tick(scenario: :healthy)
    package = intercepted

    calls = 0
    allow(TelemetryUnpackerService).to receive(:call).and_wrap_original do |original, *args, **kwargs|
      calls += 1
      raise ActiveRecord::ConnectionTimeoutError, "crash mid-unpack" if calls == 1
      original.call(*args, **kwargs)
    end

    crashed = UnpackTelemetryWorker.new
    crashed.jid = "hil-crash-jid"
    expect { crashed.perform(package[:encoded], gateway.ip_address, package[:uid]) }
      .to raise_error(ActiveRecord::ConnectionTimeoutError)

    retried = UnpackTelemetryWorker.new
    retried.jid = "hil-crash-jid"
    retried.perform(package[:encoded], gateway.ip_address, package[:uid])

    expect(gateway.reload.last_attested_at).to be_present
    # The REAL unpacker ran on the retry: the sentinel chunk reached the queue.
    expect(GatewayTelemetryWorker.jobs.size).to eq(1)
  end

  it "keeps the legacy (unsigned) path at L0 untouched" do
    legacy = Hil::QueenSimulator.new(gateway, mode: :wire)
    legacy.tick(scenario: :healthy)
    package = intercepted

    expect(TelemetryUnpackerService).to receive(:call)
      .with(anything, gateway.id, gateway_attested: false).and_call_original

    UnpackTelemetryWorker.new.perform(package[:encoded], gateway.ip_address, package[:uid])

    expect(gateway.reload.last_attested_at).to be_nil
  end
end
