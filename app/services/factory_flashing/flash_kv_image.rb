# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [FW.17] Образ журналу Flash-KV для КОЖНОГО провіжну дерева — re-provision
# (⚖️ founder 2026-09-28, 03_05 §3.8) і перший теж (⚖️ founder 2026-09-29, 03_06 §5). Конвеєр стирає обидві сторінки журналу й пише свіжий, у якому два записи.
# Анти-відкат OTA `0x15` = `clusters.ota_version_hiwater`: версії ратчета `0x13`
# немає, тож вузол стартує на K0_e з v = 0, а K_ota (від re-provision незмінний)
# не пропустить повтор старого підписаного OTA. Якір лічильника кадрів CCM
# `0x14` = 1 [SEC.41, ⚖️ founder 2026-10-05]: FC під свіжим ключем стартує біля
# нуля, а не з HRNG рівномірно в [1, 0xFFFFFE], тож 24-бітний простір увесь попереду.
#
# Дзеркало `firmware/common/flash_kv.{h,c}`: елемент — один doubleword
# `[value:32][key:8][flags 0xA5][crc16]`, заголовок сторінки — `SKV1|seq|crc` +
# `FINI|seq|crc`, «перше життя» — сторінка 0 із seq 1. Образ побайтово дорівнює
# тому, що прошивка сама лишила б після `FlashKv_Mount` на чистому флеші +
# `FlashKv_Put32(0x15, hiwater)`; golden-пін обабіч —
# `spec/services/factory_flashing/flash_kv_image_spec.rb` ⟷
# `firmware/test/test_flash_kv.c` (`test_fw17_factory_journal_*`). Зміна
# формату з одного боку червонить протилежний пін.
module FactoryFlashing
  module FlashKvImage
    BASE_ADDR  = 0x0803D000 # firmware: FLASH_KV_BASE_ADDR (сторінка 122)
    FIRST_PAGE = 122        # firmware: FLASH_KV_FIRST_PAGE
    # Стерти ОБИДВІ: вціліла сусідка з вищою seq перемогла б при Mount і
    # повернула б стару версію ратчета. Писати в неї «стерті» слова не можна —
    # на WL запрограмований doubleword повторно не пишеться (ECC).
    PAGES      = [ FIRST_PAGE, FIRST_PAGE + 1 ].freeze

    PAGE_MAGIC      = 0x534B5631 # "SKV1"
    FINI_MAGIC      = 0x46494E49 # "FINI"
    REC_FLAGS       = 0xA5
    FIRST_SEQ       = 1
    OTA_VERSION_KEY = 0x15       # firmware: SEC20_OTA_VER_KV_KEY
    FC_HIWATER_KEY  = 0x14       # firmware: FW2_FC_KV_KEY_HIWATER (fc_hiwater.h)
    FC_FLOOR        = 1          # [SEC.41] перший TX = FC 2; 0 прошивка читає як «якоря немає»

    module_function

    # Doubleword'и сторінки 122 від її початку.
    def dws(ota_hiwater:)
      raise ArgumentError, "ota_hiwater must fit u32" unless ota_hiwater.is_a?(Integer) && ota_hiwater.between?(0, 0xFFFF_FFFF)

      [ header(PAGE_MAGIC), header(FINI_MAGIC), record(OTA_VERSION_KEY, ota_hiwater), record(FC_HIWATER_KEY, FC_FLOOR) ]
    end

    # { addr => "0x…" } для `CommandBuilder`: doubleword лежить у флеші
    # little-endian (HAL_FLASH_Program пише молодше слово першим), тож за адресою
    # dw — молодше слово, за +4 — старше.
    def words(ota_hiwater:)
      dws(ota_hiwater: ota_hiwater).each_with_index.each_with_object({}) do |(dw, i), image|
        addr = BASE_ADDR + (i * 8)
        image[addr]     = format("0x%08X", dw & 0xFFFF_FFFF)
        image[addr + 4] = format("0x%08X", dw >> 32)
      end
    end

    def header(magic, seq = FIRST_SEQ)
      crc = OtaPackagerService.crc16_ccitt([ magic ].pack("N") + [ seq ].pack("n"))
      (magic << 32) | (seq << 16) | crc
    end

    def record(key, value)
      crc = OtaPackagerService.crc16_ccitt([ value ].pack("N") + [ key, REC_FLAGS ].pack("CC"))
      (value << 32) | (key << 24) | (REC_FLAGS << 16) | crc
    end
  end
end
