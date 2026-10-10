# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Downlink
  # [FW.17 · docs/03_05 §2.5] Адресна команда ОДНОМУ Солдату, підписана його
  # сесійним ключем (downlink-wire-ревізія, ⚖️ founder 2026-09-28):
  #
  #   [opcode][DID BE][DLFC_lsb BE] || CCM(body) || MIC(8)  — 0x9E 17 Б
  #
  # Королева кадр лише несе (firmware/queen/soldier_cmd_queue.h), Солдат
  # відкриває (firmware/common/downlink_ccm_open.h); примітив —
  # Cryptography::LoraCcm.encrypt_downlink. Тіла — little-endian тіла старого
  # каркаса без len і CRC.
  #
  # DLFC видається ОДИН раз, при видачі команди, і живе з нею: повторна видача —
  # той самий кадр (ті самі ключ, DLFC і тіло дають ті самі байти CCM), тож
  # Королева його дедупить, а Солдат не палить запис Flash-KV на повторі.
  #
  # Правило grace: поки ротація не підтверджена (previous_aes_key_hex є), 0x9E
  # підписано ПОПЕРЕДНІМ ключем — тим, що вузол ще тримає. Адресна команда, що
  # з'явиться поруч із 0x9E, мусить під grace чекати: видача її DLFC мусить
  # відмовляти під живим grace, інакше лічильник зсунеться з-під кадру ротації.
  module CommandFrame
    ROTATE_KEY = 0x9E
    # RETIRED, ⛔ не перевикористовувати: 0x9D з HW.30 (аудіо-пороги зрізаного пʼєзо) ·
    # 0x9A з FW.66 (смуга Лоренца FW.8 — ролі Z розведено, пристрій смуги не приймає).

    module_function

    # 0x9E ратчет-grace, що летить: ціль = key_version, ключ = попередній, DLFC —
    # той, що видав rotate! (під grace нічого іншого не видається). Grace після
    # re-provision (версія 0) ротацією не є — його закриває MIC, не 0x9E.
    def rotate_key(hardware_key)
      unless hardware_key.previous_aes_key_hex.present? && hardware_key.key_version.positive?
        raise ArgumentError, "#{hardware_key.device_uid}: ратчет-grace не відкритий — 0x9E нема з чого будувати"
      end
      raise ArgumentError, "#{hardware_key.device_uid}: DLFC ротації не видано" unless hardware_key.downlink_frame_counter.positive?

      seal(hardware_key, ROTATE_KEY, [ hardware_key.key_version ].pack("v"),
           key_hex: hardware_key.previous_aes_key_hex, dlfc: hardware_key.downlink_frame_counter)
    end

    def seal(hardware_key, opcode, body, key_hex:, dlfc:)
      Cryptography::LoraCcm.encrypt_downlink(
        key: [ key_hex ].pack("H*"),
        opcode: opcode,
        did_bytes: [ Cryptography::KeyRatchet.did_to_u32(hardware_key.device_uid) ].pack("N"),
        dlfc: dlfc,
        body: body
      )
    end
    private_class_method :seal
  end
end
