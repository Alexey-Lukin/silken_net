# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [FW.54] Парсер виводу `STM32_Programmer_CLI -r32 0x1FFF7590 12` — рядок
# виду "0x1FFF7590 : 0039002F 31385115 38323634". Формат між версіями CLI
# пливе, тому парсер keyed на базову адресу і толерантний до 0x-префіксів
# та регістру; точний формат live-CLI = bench-confirm (RUNBOOK 1.3).
# nil = не розпарсили — викликач (Session) відмовляє записом, не пише наосліп.
module FactoryFlashing
  module UidReadout
    UID_LINE = /1FFF7590\s*:\s*(.+)$/i

    module_function

    # stdout → [w0, w1, w2] (порядок регістрів) або nil.
    def words(stdout)
      m = UID_LINE.match(stdout.to_s)
      return nil unless m

      hex = m[1].scan(/\b(?:0x)?([0-9A-Fa-f]{8})\b/).flatten
      return nil if hex.size < 3

      hex.first(3).map { |w| Integer(w, 16) }
    end

    # [w0, w1, w2] → канонічний 24-hex рядок (форма trees.silicon_uid_hex).
    def uid_hex(words)
      words.map { |w| format("%08X", w) }.join
    end

    # Перше слово сторінки ключів із того самого preflight-виводу (`-r32 0x0803E000 4`):
    # 0xFFFFFFFF = чиста, магія KEYL = прошита; nil = не розпарсили.
    KEY_LINE = /0803E000\s*:\s*(.+)$/i

    def key_page_word(stdout)
      m = KEY_LINE.match(stdout.to_s)
      word = m && m[1][/\b(?:0x)?(\h{8})\b/i, 1]
      word && Integer(word, 16)
    end
  end
end
