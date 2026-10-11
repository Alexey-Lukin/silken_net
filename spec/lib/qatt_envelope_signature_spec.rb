# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "spec_helper"
require "openssl"
require_relative "../../lib/qatt_envelope_signature"

# [FW.66 (Б) · S8b] Дім повідомлення підпису QATT і його офлайн-перевірки. Оракули тут НЕЗАЛЕЖНІ від
# модуля: повідомлення збирається вручну з байтів, а golden-вектор — той самий, що пінить C-дзеркало
# прошивки (`firmware/test/test_queen_attest.c`).
RSpec.describe QattEnvelopeSignature do
  let(:key) { OpenSSL::PKey.generate_key("ED25519") }
  let(:public_key_hex) { key.raw_public_key.unpack1("H*") }
  let(:uid) { "SNET-Q-0000ABCD" }
  let(:body) { [ 0x02, 1_750_000_000, 7 ].pack("CNN") + ("\x00" * 8) + Random.bytes(32) }

  def sign(message) = key.sign(nil, message)
  def envelope_for(signed_uid) = body + sign("SLKN-QATT2".b + [ signed_uid.bytesize ].pack("C") + signed_uid.b + body)

  it "приймає підпис Королеви над конвертом і її UID" do
    expect(described_class.verify(envelope_for(uid), uid: uid, public_key_hex: public_key_hex)).to be(true)
  end

  it "відкидає конверт, підписаний для іншого UID (сплайс між шлюзами)" do
    expect(described_class.verify(envelope_for("SNET-Q-FFFF0000"), uid: uid, public_key_hex: public_key_hex)).to be(false)
  end

  it "відкидає мутацію S + L — строго, як сервер після SEC.43" do
    envelope = envelope_for(uid)
    sig = envelope.byteslice(-64, 64)
    s = sig.byteslice(32, 32).reverse.unpack1("H*").to_i(16) + described_class::GROUP_ORDER
    skip "S + L переповнює 253 біти для цього підпису" if s >= 2**253
    malleated = envelope.byteslice(0, envelope.bytesize - 64) + sig.byteslice(0, 32) + [ s.to_s(16).rjust(64, "0") ].pack("H*").reverse

    expect(described_class.verify(malleated, uid: uid, public_key_hex: public_key_hex)).to be(false)
  end

  it "судить рамку без ключа: версія, мінімальна довжина й residue" do
    envelope = envelope_for(uid)

    expect(described_class.shape_ok?(envelope)).to be(true)
    expect(described_class.shape_ok?("\x01".b + envelope.byteslice(1..))).to be(false)
    expect(described_class.shape_ok?(envelope + "\x00")).to be(false)
    expect(described_class.verify(envelope + "\x00", uid: uid, public_key_hex: public_key_hex)).to be(false)
  end

  it "golden-вектор прошивки: конверт C-дзеркала перевіряється ключем із його сіда" do
    health = [ 0x00, 0x14, 0xBE, 42, 3, 1, 17, 0 ].pack("C8") # uptime 5310 хв, cifo 42, drops 3, fail 1, csq 17
    iv_ct = [ "00112233445566778899aabbccddeeff" \
              "deadbeef0102030405060708090a0b0cc0ffee00102030405060708090a0b0c0" ].pack("H*")
    sig = [ "c7b5e07db501233eed0a43d10a1988f4ba0b0a3a59ac2d39cf0c542b7be2d266" \
            "82bf0a1d31533b3405ae2f691648308e7ddbfd0e507934ce235161f572c2b40f" ].pack("H*")
    golden = [ 0x02, 1_750_000_000, 7 ].pack("CNN") + health + iv_ct + sig

    expect(described_class.verify(golden, uid: "SNET-Q-A1B2C3D4",
                                          public_key_hex: "963058b4a0e2686c7dfcd823bd59643f941aebffbba13336ed2d41d2fd22d2b0"))
      .to be(true)
  end

  it "самоперевірка OpenSSL цієї машини: вектор RFC 8032 приймається, його мутація S + L — ні" do
    expect(described_class.self_test).to be(true)
  end
end
