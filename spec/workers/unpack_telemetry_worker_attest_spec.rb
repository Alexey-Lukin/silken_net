# frozen_string_literal: true

require "rails_helper"

# [L1 QATT] Trust-origin L1 — Queen-attestation батч-конверта.
# Канон: 05_02 «Trust-origin ladder» + 03_05 §2.2 (wire);
# firmware-дзеркало: firmware/common/queen_attest.h + test_queen_attest.c.
#
# Golden-KAT нижче — ТІ САМІ входи, що в firmware/test/test_queen_attest.c:
# C-сторона деривує підпис через Monocypher і звіряє з OpenSSL; ця спека —
# третя незалежна реалізація (ruby `ed25519` gem). Усі три мусять збігатися
# байт-у-байт (Ed25519 детермінований, RFC 8032).
RSpec.describe UnpackTelemetryWorker, type: :worker do
  let(:cluster) { create(:cluster) }
  let(:gateway) { create(:gateway, cluster: cluster, ip_address: "10.0.0.1") }
  let(:key_record) { create(:hardware_key, device_uid: gateway.uid) }

  # Жива пара для повних worker-сценаріїв (golden-пара — окремо нижче)
  let(:keypair) { Ed25519Crypto::SigningService.generate_keypair }

  before do
    key_record.update!(ed25519_public_key_hex: keypair[:public_key_hex])
    allow(TelemetryUnpackerService).to receive(:call)
    allow(Turbo::StreamsChannel).to receive(:broadcast_prepend_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_remove_to)
    allow(ActionCable.server).to receive(:broadcast)
  end

  # Шифрування як у Queen: [IV:16][AES-256-CBC ct, zero-pad]
  def encrypt_body(data, key)
    cipher = OpenSSL::Cipher.new("aes-256-cbc")
    cipher.encrypt
    cipher.key = key
    iv = cipher.random_iv
    padding = (16 - (data.bytesize % 16)) % 16
    iv + cipher.update(data + ("\x00" * padding)) + cipher.final
  end

  # Підписаний конверт РІВНО як Flush_Cache_To_Rails:
  # [ver:1][ts:4 BE][seq:4 BE][IV][ct][sig:64];
  # message = TAG ‖ uid_len ‖ uid ‖ <усе без хвостового sig>.
  def build_signed_payload(seed_hex:, uid:, iv_ct:, ts: 1_750_000_000, seq: 7, version: 0x01)
    header = [ version, ts, seq ].pack("CNN")
    body = header + iv_ct
    message = described_class::QATT_DOMAIN_TAG + [ uid.bytesize ].pack("C") + uid.b + body
    sig_hex = Ed25519Crypto::SigningService.sign(seed_hex, message)
    body + [ sig_hex ].pack("H*")
  end

  describe "golden-KAT parity (дзеркало firmware/test/test_queen_attest.c)" do
    # "SILKEN-NET-L1-QATT-GOLDEN-SEED!!" — ASCII-байти C-масиву GOLDEN_SEED
    let(:golden_seed_hex) { "SILKEN-NET-L1-QATT-GOLDEN-SEED!!".unpack1("H*") }
    let(:golden_uid)      { "SNET-Q-A1B2C3D4" }
    let(:golden_iv)       { [ "00112233445566778899aabbccddeeff" ].pack("H*") }
    let(:golden_ct) do
      [ "deadbeef0102030405060708090a0b0cc0ffee00102030405060708090a0b0c0" ].pack("H*")
    end
    let(:golden_pub_hex) { "963058b4a0e2686c7dfcd823bd59643f941aebffbba13336ed2d41d2fd22d2b0" }
    let(:golden_sig_hex) do
      "d3648e0d4c233782d3d8510a4d582d8e110d15a62b7d609807c2f722a040db12" \
        "ee6359dd44cd6efac0f2c670f44062eae35fa996b84589977cb04791ef24a50b"
    end

    it "derives the same public key as Monocypher/OpenSSL" do
      expect(Ed25519Crypto::SigningService.public_key_from_seed(golden_seed_hex))
        .to eq(golden_pub_hex)
    end

    it "produces the byte-identical envelope signature" do
      payload = build_signed_payload(
        seed_hex: golden_seed_hex, uid: golden_uid, iv_ct: golden_iv + golden_ct
      )
      expect(payload.byteslice(-64, 64).unpack1("H*")).to eq(golden_sig_hex)
      # residue-дискримінатор: підписаний ≡ 9 (mod 16), legacy ≡ 0
      expect(payload.bytesize % 16).to eq(described_class::QATT_RESIDUE)
    end
  end

  describe "#perform з підписаним конвертом" do
    let(:raw_data) { "ATTESTED_BATCH_DATA_123" }
    let(:iv_ct)    { encrypt_body(raw_data, key_record.binary_key) }
    let(:payload)  { build_signed_payload(seed_hex: keypair[:seed_hex], uid: gateway.uid, iv_ct: iv_ct) }
    let(:encoded)  { Base64.strict_encode64(payload) }

    it "верифікує підпис, зрізає конверт і маркує батч атестованим" do
      described_class.new.perform(encoded, "10.0.0.1", gateway.uid)

      expect(TelemetryUnpackerService).to have_received(:call)
        .with(anything, gateway.id, gateway_attested: true)
    end

    it "ставить gateways.last_attested_at" do
      expect { described_class.new.perform(encoded, "10.0.0.1", gateway.uid) }
        .to change { gateway.reload.last_attested_at }.from(nil)
    end

    it "передає сервісу РІВНО legacy-байти [IV][ct] (конверт зрізано)" do
      decrypted = nil
      allow(TelemetryUnpackerService).to receive(:call) { |data, _id, **| decrypted = data }

      described_class.new.perform(encoded, "10.0.0.1", gateway.uid)

      expect(decrypted).to start_with(raw_data)
    end

    it "відкидає підроблений ciphertext (bad signature) без retry" do
      tampered = payload.dup
      tampered.setbyte(20, tampered.getbyte(20) ^ 0x01) # байт усередині IV/ct
      described_class.new.perform(Base64.strict_encode64(tampered), "10.0.0.1", gateway.uid)

      expect(TelemetryUnpackerService).not_to have_received(:call)
    end

    it "відкидає replay того самого підписаного батча (nonce)" do
      described_class.new.perform(encoded, "10.0.0.1", gateway.uid)
      described_class.new.perform(encoded, "10.0.0.1", gateway.uid)

      expect(TelemetryUnpackerService).to have_received(:call).once
    end

    it "блокує replay через Solid-Cache fallback при відмові Redis" do
      allow(Kredis).to receive(:redis).and_raise(Redis::BaseConnectionError, "Connection refused")
      allow(SilkenNet::Metrics::QATT_NONCE_FALLBACK_TOTAL).to receive(:increment)

      described_class.new.perform(encoded, "10.0.0.1", gateway.uid)
      described_class.new.perform(encoded, "10.0.0.1", gateway.uid)

      expect(TelemetryUnpackerService).to have_received(:call).once
      expect(SilkenNet::Metrics::QATT_NONCE_FALLBACK_TOTAL).to have_received(:increment).twice
    end

    it "відкидає конверт невідомої версії (чесний drop, гучна метрика)" do
      v2 = build_signed_payload(seed_hex: keypair[:seed_hex], uid: gateway.uid, iv_ct: iv_ct, version: 0x02)
      described_class.new.perform(Base64.strict_encode64(v2), "10.0.0.1", gateway.uid)

      expect(TelemetryUnpackerService).not_to have_received(:call)
    end

    it "не дає сплайснути батч у URI іншого шлюзу (UID вшито в підпис)" do
      other = create(:gateway, cluster: cluster, ip_address: "10.0.0.2")
      create(:hardware_key, device_uid: other.uid,
                            ed25519_public_key_hex: keypair[:public_key_hex])

      described_class.new.perform(encoded, "10.0.0.2", other.uid)

      expect(TelemetryUnpackerService).not_to have_received(:call)
    end

    context "when pubkey не зареєстровано" do
      before { key_record.update!(ed25519_public_key_hex: nil) }

      it "обробляє як L0 (gateway_attested: false), не караючи телеметрію" do
        described_class.new.perform(encoded, "10.0.0.1", gateway.uid)

        expect(TelemetryUnpackerService).to have_received(:call)
          .with(anything, gateway.id, gateway_attested: false)
      end

      it "не ставить last_attested_at" do
        described_class.new.perform(encoded, "10.0.0.1", gateway.uid)
        expect(gateway.reload.last_attested_at).to be_nil
      end
    end

    it "битий ЗБЕРЕЖЕНИЙ pubkey (misprovisioning) → L0, не drop" do
      # update_column обходить length-валідацію моделі — симулюємо битий стан
      key_record.update_column(:ed25519_public_key_hex, "deadbeef")

      described_class.new.perform(encoded, "10.0.0.1", gateway.uid)

      expect(TelemetryUnpackerService).to have_received(:call)
        .with(anything, gateway.id, gateway_attested: false)
    end
  end

  describe "#perform з legacy-батчем (L0, незмінна поведінка)" do
    it "проходить як gateway_attested: false" do
      legacy = encrypt_body("LEGACY_BATCH", key_record.binary_key)
      described_class.new.perform(Base64.strict_encode64(legacy), "10.0.0.1", gateway.uid)

      expect(TelemetryUnpackerService).to have_received(:call)
        .with(anything, gateway.id, gateway_attested: false)
    end
  end
end
