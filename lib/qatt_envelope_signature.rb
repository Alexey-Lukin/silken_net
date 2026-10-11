# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "digest"
require "openssl"

# QattEnvelopeSignature — один дім повідомлення підпису QATT-конверта Королеви та його офлайн-перевірки
# (`03_05 §2.2`; wire-дім розкладки — `firmware/common/queen_attest.h`). Лише stdlib: офлайн-верифікатори
# (`scripts/verify_*_bundle.rb`) ганяються без Rails і без гема `ed25519`.
#
# Конверт: [ver:1=0x02][unix_ts:4][flush_seq:4][health:8][IV:16][ct][sig:64]. Підписано
# DOMAIN_TAG ‖ uid_len:1 ‖ uid ‖ <конверт без хвостового підпису> — UID Королеви вшито в підпис,
# тож батч не сплайснути між шлюзами.
#
# Перевірка — OpenSSL Ed25519, а він СТРОГИЙ (S < L, RFC 8032 §5.1.7). Сервер судить тим самим правилом
# (`Ed25519Crypto::SigningService.verify`, SEC.43), тож множини прийнятих підписів у сервера й
# офлайн-верифікатора однакові: інакше мутований підпис S + L, прийнятий сервером, читався б офлайн
# підробкою назавжди.
#
# Один дім і серверної РОЗКЛАДКИ конверта: `UnpackTelemetryWorker` лише посилається на константи нижче,
# а пін `qatt_envelope` (lib/canonical_block_pins.yml) судить саме їх — C-половина
# (`firmware/common/queen_attest.h`) звіряється з ними руками.
module QattEnvelopeSignature
  DOMAIN_TAG = "SLKN-QATT2".b.freeze
  VERSION = 0x02
  HEALTH_LEN = 8 # [uptime_min:u24 BE][cifo_fill][lora_rx_drops][coap_fail][csq][flags]
  HEADER_LEN = 17 # ver:1 + unix_ts:4 + flush_seq:4 + health:8
  IV_LEN = 16
  SIG_LEN = 64
  MIN_LEN = HEADER_LEN + IV_LEN + SIG_LEN
  # Підписаний конверт ≡ RESIDUE (mod 16), legacy [IV][ct] ≡ 0 — дискримінатор довжини.
  RESIDUE = MIN_LEN % 16
  # Порядок групи Ed25519 (RFC 8032 §5.1) — для самоперевірки строгості нижче.
  GROUP_ORDER = (2**252) + 27_742_317_777_372_353_535_851_937_790_883_648_493
  # RFC 8032 §7.1 TEST 1: порожнє повідомлення.
  RFC8032_TEST1_PUBLIC_KEY_HEX = "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"
  RFC8032_TEST1_SIGNATURE_HEX = "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555" \
                                "fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b"

  module_function

  def message(uid, envelope)
    uid = uid.to_s.b
    DOMAIN_TAG + [ uid.bytesize ].pack("C") + uid + envelope.b.byteslice(0, envelope.bytesize - SIG_LEN)
  end

  def signature(envelope) = envelope.b.byteslice(-SIG_LEN, SIG_LEN)

  def sha256(envelope) = Digest::SHA256.digest(envelope.b)

  # Рамка конверта, яку можна судити без ключа.
  def shape_ok?(envelope)
    envelope = envelope.b
    envelope.bytesize >= MIN_LEN && (envelope.bytesize % 16) == RESIDUE && envelope.getbyte(0) == VERSION
  end

  # true — підпис Королеви з `public_key_hex` над цим конвертом і цим UID.
  def verify(envelope, uid:, public_key_hex:)
    return false unless shape_ok?(envelope) && public_key_hex.to_s.match?(/\A\h{64}\z/)

    key = OpenSSL::PKey.new_raw_public_key("ED25519", [ public_key_hex ].pack("H*"))
    key.verify(nil, signature(envelope), message(uid, envelope))
  rescue OpenSSL::PKey::PKeyError
    false
  end

  # Самоперевірка OpenSSL машини аудитора: вектор RFC 8032 приймається, а його мутація S + L — ні.
  # Нестрогий верифікатор приймав би підписи, яких сервер не приймав (SEC.43), і навпаки.
  def self_test
    key = OpenSSL::PKey.new_raw_public_key("ED25519", [ RFC8032_TEST1_PUBLIC_KEY_HEX ].pack("H*"))
    signature = [ RFC8032_TEST1_SIGNATURE_HEX ].pack("H*")
    s = signature.byteslice(32, 32).reverse.unpack1("H*").to_i(16) + GROUP_ORDER
    malleated = signature.byteslice(0, 32) + [ s.to_s(16).rjust(64, "0") ].pack("H*").reverse
    key.verify(nil, signature, "") && !verify_raw(key, malleated)
  rescue OpenSSL::PKey::PKeyError, NotImplementedError
    false
  end

  def verify_raw(key, signature)
    key.verify(nil, signature, "")
  rescue OpenSSL::PKey::PKeyError
    false
  end
end
