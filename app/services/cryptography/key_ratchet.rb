# frozen_string_literal: true

require "openssl"

# [FW.17] Hash-Ratchet ротація per-device LoRa AES-128 ключа.
#
# Ключ ніколи не передається мережею: команда `CMD_ROTATE_KEY` (0x9E,
# OtaPackagerService.build_rotate_key_block) несе лише target_version —
# обидва кінці синхронно деривують наступний ключ. Один крок:
#
#   K_{v+1} = HMAC-SHA256(key = K_v,
#                         msg = 0x01 ‖ "silken-lora-ratchet-v1" ‖ 0x00
#                               ‖ DID_be4 ‖ 0x0080)[0..15]
#
# — KDF in Counter Mode за NIST SP 800-108 (i=1, Label, Context = DID,
# L = 128 біт). Дзеркало firmware: `firmware/common/key_ratchet.h`
# (pure-C, той самий golden-KAT — byte-parity пінується спеками обабіч).
#
# Властивості (чесна модель — канон docs/03_05 §3.6): BACKWARD secrecy —
# витік K_v не відкриває попередні ключі й записаний раніше трафік
# (вимога GDPR/ISO 27001/NIST SP 800-57); майбутні ключі з K_v похідні —
# відновлення після компрометації = re-provisioning або ECDH-alt.
# Інтеграція з Dual-Key Grace Period (HardwareKey): backend ротує при
# dispatch'і команди, старий ключ живе у previous_aes_key_hex до першого
# успішного decrypt новим (= неявний per-device ACK).
module Cryptography
  module KeyRatchet
    LABEL    = "silken-lora-ratchet-v1"
    KEY_LEN  = 16
    # Стеля стрибка версій за одну команду — дзеркало KEY_RATCHET_MAX_JUMP.
    MAX_JUMP = 8

    class InputError < ArgumentError; end

    module_function

    # Один крок ratchet'а. current_key — 16-байтний binary, did — uint32.
    # Повертає 16-байтний binary наступного ключа.
    def next_key(current_key, did)
      raise InputError, "key must be #{KEY_LEN} bytes" unless current_key&.bytesize == KEY_LEN

      msg = "\x01".b + LABEL + "\x00".b + [ did ].pack("N") + [ 128 ].pack("n")
      OpenSSL::HMAC.digest("SHA256", current_key, msg).byteslice(0, KEY_LEN)
    end

    # HEX-зручність для HardwareKey.aes_key_hex (32 HEX, upcase).
    def next_key_hex(current_key_hex, did)
      next_key([ current_key_hex ].pack("H*"), did).unpack1("H*").upcase
    end

    # Просунути ключ з версії from до to (включно). Та сама версійна
    # дисципліна, що Key_Ratchet_Steps у firmware: лише вперед, стрибок
    # ≤ MAX_JUMP — інакше nil (стан викликача незмінний).
    def advance_hex(current_key_hex, did, from:, to:)
      steps = to - from
      return nil if steps <= 0 || steps > MAX_JUMP

      steps.times.reduce(current_key_hex) { |hex, _| next_key_hex(hex, did) }
    end
  end
end
