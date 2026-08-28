# SPDX-License-Identifier: AGPL-3.0-or-later
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
  # [ARCH.54] wire-mode = підписаний v2 empty-flush heartbeat (health у
  # header'і) — unsigned wire health у протоколі більше не існує.
  let(:simulator) { Hil::QueenSimulator.new(gateway, mode: :wire) }

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

  it "attests a simulator-signed heartbeat end-to-end down to the DB markers" do
    simulator.tick(scenario: :healthy)
    package = intercepted

    # [ARCH.54] Heartbeat ct=0: unpack легально скипається — батча нема,
    # пульс іде з ПІДПИСАНОГО header'а (enqueue_envelope_health).
    allow(TelemetryUnpackerService).to receive(:call)

    UnpackTelemetryWorker.new.perform(package[:encoded], gateway.ip_address, package[:uid])

    expect(TelemetryUnpackerService).not_to have_received(:call)
    expect(gateway.reload.last_attested_at).to be_present
    expect(GatewayTelemetryWorker.jobs.size).to eq(1)
    stats = GatewayTelemetryWorker.jobs.last["args"].last
    expect(stats).to include("uptime_min", "cifo_fill", "cellular_signal_csq")
  end

  it "rejects a tampered ciphertext with the bad-signature metric" do
    simulator.tick(scenario: :healthy)
    package = intercepted
    tampered = package[:raw].dup
    tampered.setbyte(30, tampered.getbyte(30) ^ 0x01) # inside IV, past the 17-byte header
    allow(SilkenNet::Metrics::COAP_PACKETS_RECEIVED_TOTAL).to receive(:increment)

    allow(TelemetryUnpackerService).to receive(:call)

    UnpackTelemetryWorker.new.perform(Base64.strict_encode64(tampered), gateway.ip_address, package[:uid])

    expect(TelemetryUnpackerService).not_to have_received(:call)
    expect(gateway.reload.last_attested_at).to be_nil
    expect(SilkenNet::Metrics::COAP_PACKETS_RECEIVED_TOTAL)
      .to have_received(:increment).with(labels: { status: "attest_bad_signature" })
  end

  it "rejects a replay of the same envelope via the nonce (first pass attests)" do
    simulator.tick(scenario: :healthy)
    package = intercepted
    allow(SilkenNet::Metrics::COAP_PACKETS_RECEIVED_TOTAL).to receive(:increment)

    UnpackTelemetryWorker.new.perform(package[:encoded], gateway.ip_address, package[:uid])
    expect(gateway.reload.last_attested_at).to be_present
    expect(GatewayTelemetryWorker.jobs.size).to eq(1)

    UnpackTelemetryWorker.new.perform(package[:encoded], gateway.ip_address, package[:uid])

    # Replay не подвоює пульс — nonce ріже ДО health-енкʼю.
    expect(GatewayTelemetryWorker.jobs.size).to eq(1)
    expect(SilkenNet::Metrics::COAP_PACKETS_RECEIVED_TOTAL)
      .to have_received(:increment).with(labels: { status: "attest_replay" })
  end

  it "downgrades to L0 (:unverified) when the registered pubkey is wiped — provisioning gap" do
    simulator.tick(scenario: :healthy)
    package = intercepted
    gateway.hardware_key.update!(ed25519_public_key_hex: nil)

    # :unverified → конверт зрізано, але heartbeat ct=0 без атестації не
    # несе НІЧОГО (нема ні батча, ні довіреного пульсу) — чесний no-op.
    allow(TelemetryUnpackerService).to receive(:call)

    UnpackTelemetryWorker.new.perform(package[:encoded], gateway.ip_address, package[:uid])

    expect(TelemetryUnpackerService).not_to have_received(:call)
    expect(gateway.reload.last_attested_at).to be_nil
    expect(GatewayTelemetryWorker.jobs).to be_empty
  end

  # Конверт v2 з НЕПОРОЖНІМ ct руками (симулятор емить лише heartbeat) —
  # для crash-вікна, де unpack мусить реально бігти.
  def signed_batch_envelope!(payload_str)
    seed_hex = SecureRandom.hex(32)
    gateway.hardware_key.update!(
      ed25519_public_key_hex: Ed25519Crypto::SigningService.public_key_from_seed(seed_hex)
    )
    cipher = OpenSSL::Cipher.new("aes-256-cbc")
    cipher.encrypt
    cipher.key = gateway.hardware_key.binary_key
    iv = cipher.random_iv
    cipher.padding = 0
    iv_ct = iv + cipher.update(payload_str.b) + cipher.final
    health = [ 0, 0, 60, 5, 0, 0, 20, 0 ].pack("C8")
    body = [ 0x02, Time.current.to_i, 3 ].pack("CNN") + health + iv_ct
    message = UnpackTelemetryWorker::QATT_DOMAIN_TAG +
              [ gateway.uid.bytesize ].pack("C") + gateway.uid.b + body
    Base64.strict_encode64(
      body + [ Ed25519Crypto::SigningService.sign(seed_hex, message) ].pack("H*")
    )
  end

  it "recovers an attested BATCH after a mid-unpack crash — Sidekiq retry with the same jid resumes" do
    encoded = signed_batch_envelope!("BATCH_PAYLOAD_16")

    calls = 0
    allow(TelemetryUnpackerService).to receive(:call).and_wrap_original do |original, *args, **kwargs|
      calls += 1
      raise ActiveRecord::ConnectionTimeoutError, "crash mid-unpack" if calls == 1
      original.call(*args, **kwargs)
    end

    crashed = UnpackTelemetryWorker.new
    crashed.jid = "hil-crash-jid"
    expect { crashed.perform(encoded, gateway.ip_address, gateway.uid) }
      .to raise_error(ActiveRecord::ConnectionTimeoutError)

    retried = UnpackTelemetryWorker.new
    retried.jid = "hil-crash-jid"
    retried.perform(encoded, gateway.ip_address, gateway.uid)

    expect(gateway.reload.last_attested_at).to be_present
    expect(TelemetryUnpackerService).to have_received(:call).twice
    # [ARCH.54] Пульс енкʼюється у :attested-гілці (до unpack) — crash в
    # unpack'у НЕ губить його; resume не дублює батч, пульс іде щопроходу.
    expect(GatewayTelemetryWorker.jobs.size).to eq(2)
  end

  it "keeps the legacy (unsigned) path at L0 untouched" do
    # [ARCH.54] Симулятор unsigned більше не емить (health = лише attested);
    # legacy-БАТЧ (телеметрія без конверта) будуємо руками — pre-QATT Королева.
    cipher = OpenSSL::Cipher.new("aes-256-cbc")
    cipher.encrypt
    cipher.key = gateway.hardware_key.binary_key
    iv = cipher.random_iv
    cipher.padding = 0
    legacy = iv + cipher.update("LEGACY_BATCH_16B") + cipher.final

    allow(TelemetryUnpackerService).to receive(:call)
      .with(anything, gateway.id, gateway_attested: false, received_at: nil).and_call_original

    UnpackTelemetryWorker.new.perform(Base64.strict_encode64(legacy),
                                      gateway.ip_address, gateway.uid)

    expect(TelemetryUnpackerService).to have_received(:call)
      .with(anything, gateway.id, gateway_attested: false, received_at: nil)
    expect(gateway.reload.last_attested_at).to be_nil
    expect(GatewayTelemetryWorker.jobs).to be_empty
  end
end
