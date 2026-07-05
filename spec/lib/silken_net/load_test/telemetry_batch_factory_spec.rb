# frozen_string_literal: true

require "rails_helper"

# Drift-guard: factory-pack — runtime-дзеркало TelemetryUnpackerService::
# PAYLOAD_FORMAT (той самий контракт, що spec/support TelemetryChunkHelper та
# bin/forest_simulator). Round-trip тут доводить байт-рівність БЕЗ spec-coupling:
# якщо wire-формат зсунеться, decrypt→unpack тут впаде раніше за прод.
RSpec.describe SilkenNet::LoadTest::TelemetryBatchFactory do
  describe ".encrypted_batch (round-trip)" do
    it "дешифрується назад у ті самі 21-байт chunk-значення (контракт unpacker'а)" do
      key  = SecureRandom.bytes(32)
      dids = [ 0x0000000A, 0x0000000B ]

      batch = described_class.encrypted_batch(
        key: key, dids: dids,
        voltage_mv: 4123, temperature_c: 22, acoustic: 7, growth_points: 20
      )

      # AES-256-CBC decrypt дзеркалом UnpackTelemetryWorker#decrypt_aes (padding=0).
      iv     = batch.byteslice(0, 16)
      cipher = OpenSSL::Cipher.new("aes-256-cbc")
      cipher.decrypt
      cipher.key     = key
      cipher.iv      = iv
      cipher.padding = 0
      plain = cipher.update(batch.byteslice(16..)) + cipher.final

      chunk = plain.byteslice(0, 21)
      expect(chunk.byteslice(0, 4).unpack1("N")).to eq(0x0A) # L2 DID
      expect(-chunk.getbyte(4)).to eq(-60)                   # RSSI (wire 60 → actual -60)

      did, voltage, temp, acoustic, _metab, status, =
        chunk.byteslice(5, 16).unpack(TelemetryUnpackerService::PAYLOAD_FORMAT)
      expect([ did, voltage, temp, acoustic ]).to eq([ 0x0A, 4123, 22, 7 ])
      expect(status & 0x1F).to eq(20)          # growth_points у homeostasis-band
      expect((status >> 5) & 0x03).to eq(0)    # bio_status = homeostasis
    end

    it "пакує 21 байт/дерево, вирівняно до 16-байтового AES-блоку" do
      batch   = described_class.encrypted_batch(key: SecureRandom.bytes(32), dids: [ 1, 2, 3 ])
      ct_size = batch.bytesize - 16 # мінус IV
      expect(ct_size % 16).to eq(0)
      expect(ct_size).to be >= 3 * 21
    end
  end

  describe ".coap_datagram" do
    it "будує CoAP CON PUT, який Брама маршрутизує як telemetry_batch" do
      uid      = "SNET-Q-DEADBEEF"
      datagram = described_class.coap_datagram(gateway_uid: uid, payload: "abc".b)

      intake = CoapServerPdu.handle_telemetry_datagram(datagram)
      expect(intake.status).to eq(:telemetry_batch)
      expect(intake.gateway_uid).to eq(uid)
      expect(intake.payload).to eq("abc".b)
    end
  end

  describe ".random_payload" do
    it "повертає запитаний розмір (structural intake-flood)" do
      expect(described_class.random_payload(64).bytesize).to eq(64)
    end
  end
end
