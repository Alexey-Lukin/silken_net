# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [SEC.3] Factory Flashing — STM32CubeProgrammer CLI command emission.
#
# Generates the canonical sequence of `STM32_Programmer_CLI` invocations that
# burn a per-device key payload into the Protected Flash Sector and lock the
# chip. The flash layout MUST match firmware constants
# (firmware/soldier/main.c §FLASH_KEY_ADDR — post-ARCH.42):
#
#   0x0803E000  [magic "KEYL" :4 ][ aes_lora_key :16 ]                 # Tree = session (per-device); Gateway = broadcast-значення (див. нижче)
#   0x0803E014  [magic "LSED" :4 ][ k_seed       :32 ]                 # Tree only
#   0x0803E040  [magic "KEYC" :4 ][ aes_coap_key :32 ]                 # Gateway only
#   0x0803E064  [magic "EDSK" :4 ][ ed25519_seed :32 ]                 # Gateway only — L1 QATT
#   0x0803E800  [magic "KOTA" :4 ][ k_ota        :32 ]                 # Tree only — FW.23 OTA dual-gate (стор. 125; 0x0803D000 належить Flash-KV)
#   0x0803E828  [magic "KEYB" :4 ][ bcast_key    :16 ]                 # Tree only — FW.2 (в) cluster control-plane; +40 (не +36): dw-вирівнювання WL
#   0x0803D000  [журнал Flash-KV: SKV1 · FINI · 0x15 ]                 # Tree re-provision only — FW.17 (FlashKvImage); стор. 122–123 стираються обидві
#
# [FW.2 гейт (в), двоключова модель] Gateway KEYL-слот прошивається
# BROADCAST-значенням (HKDF cluster-домену, derive_broadcast_key) — Королева
# живе цим ключем як єдиним LoRa-ключем (шифрує downlink, читає 0x55/0x56).
# До 2026-07-03 Gateway-гілка КЕYL не писала взагалі («LoRa slot unused»),
# а Queen Load_AES_Key() без magic = Error_Handler → фабрична Королева
# цеглилась на першому boot. Tree KEYL лишається session (per-device).
#
# Output is an Array<String> — one shell command per element. Callers pipe it
# through Executor (dry-run prints to stdout; --execute spawns subprocesses).
module FactoryFlashing
  class CommandBuilder
    FLASH_OTA_KEY_ADDR  = "0x0803E800"   # Сторінка 125 за KEYL-сторінкою — FW.23 per-cluster K_ota (firmware: FLASH_OTA_KEY_ADDR)
    FLASH_KEY_ADDR      = "0x0803E000"
    UID_BASE_ADDR       = "0x1FFF7590"   # 96-біт silicon UID — ті самі три слова читає firmware did_derive.h
    FLASH_SEED_ADDR     = "0x0803E014"   # FLASH_KEY_ADDR + 4 (magic) + 16 (key)
    FLASH_COAP_KEY_ADDR = "0x0803E040"   # After K_seed (4 magic + 32 = 36 bytes) — see Queen flash layout
    FLASH_EDSK_ADDR     = "0x0803E064"   # After CoAP key (4 magic + 32) — L1 QATT голос Королеви
    FLASH_BCAST_KEY_ADDR = "0x0803E828"  # K_ota (36B) + 4B dw-паддінг — FW.2 (в) KEYB (firmware: FLASH_BCAST_KEY_ADDR)

    KOTA_MAGIC = "0x4B4F5441" # "KOTA" OTA HMAC key magic (firmware: FLASH_OTA_KEY_MAGIC) — FW.23
    KEYB_MAGIC = "0x4B455942" # "KEYB" cluster broadcast key magic (firmware: FLASH_BCAST_KEY_MAGIC) — FW.2 (в)
    KEYL_MAGIC = "0x4B45594C" # "KEYL" LoRa key magic (firmware: FLASH_KEY_MAGIC)
    LSED_MAGIC = "0x4C534544" # "LSED" Lorenz K_seed magic (firmware: FLASH_SEED_MAGIC)
    KEYC_MAGIC = "0x4B455943" # "KEYC" CoAP key magic (firmware: FLASH_COAP_KEY_MAGIC)
    EDSK_MAGIC = "0x4544534B" # "EDSK" Ed25519 seed magic (firmware: FLASH_ED25519_SEED_MAGIC)

    PROGRAMMER = "STM32_Programmer_CLI"
    # Кожен рядок транскрипту — окремий процес CLI, а з'єднання живе лише в межах
    # одного виклику: `-c` несе КОЖЕН рядок, у формі вендорського
    # STM32WLScripts/SetRDPLevelCM4.bat — під скидом (`mode=UR` ловить вектор скиду
    # до першої інструкції). Ціль інакше не стоїть: після `-e` прошивка без KEYL
    # іде в Error_Handler → NVIC_SystemReset кожні ~100 мс, а між флашами спить у
    # STOP2. UR означає апаратний скид, тож NRST на джизі обовʼязковий.
    CONNECT = "-c port=SWD mode=UR"
    # Станція з кількома ST-LINK: без `sn=` кожен рядок бере зонд `index` 0 заново
    # (UM2237: `sn` і `index` взаємовиключні, дефолт — index 0), а паспорт плати
    # звіряє лише перший рядок — наступний `-w32` міг би лягти на іншу плату.
    # Серійник — властивість станції (`STLINK_SN`) і йде в argv підпроцесу через
    # шелл, тож лише алфанумерика.
    PROBE_SN = /\A[0-9A-Za-z]{1,64}\z/

    FLASH_BASE      = 0x08000000
    FLASH_PAGE_SIZE = 0x800        # WL: сторінка 2 КБ; код сектора для `-e` = номер сторінки — bench-confirm, 00_07 SEC.3
    ERASED_WORD     = "0xFFFFFFFF"

    # @param session   [ProvisioningSession]
    # @param device    [Tree|Gateway]
    # @param aes_key_hex     [String] 32 hex (Tree LoRa) or 64 hex (Gateway CoAP)
    # @param lorenz_seed_hex [String, nil] 64 hex; required for Tree
    # @param ota_hmac_hex    [String, nil] 64 hex; required for Tree — per-cluster
    #   K_ota (OtaHmacKeyService, FW.23). До 2026-06-11 K_ota емітувала ЛИШЕ
    #   superseded ATECC-гілка B — Гілка A не писала його взагалі, тож
    #   Load_Ota_Hmac_Key не знаходив magic і OTA був вічно fail-closed.
    # @param ed25519_seed_hex [String, nil] 64 hex; Gateway-only (L1 QATT) —
    #   генерується Session'ом на фабричному хості (SecureRandom, НЕ HKDF),
    #   у БД персиститься лише деривований pubkey. nil → Queen лишається L0.
    # @param bcast_key_hex [String, nil] 32 hex; required (обидва типи й обидві
    #   гілки) — FW.2 (в) cluster control-plane ключ (derive_broadcast_key):
    #   Tree → KEYB-слот, Gateway → її KEYL-слот (без нього Королева цеглиться
    #   на boot, а Солдат без KEYB в обох ерах мовчить Королеві: з 2026-09-28 KEYB —
    #   амбієнт і ECB-білда, тож глухне не лише downlink, а й аплінк).
    # @param kv_journal_words [Hash, nil] Tree-only, re-provision — образ журналу
    #   Flash-KV (FlashKvImage.words): обидві його сторінки стираються, навіть та,
    #   у яку образ нічого не пише (FW.17, 03_05 §3.8).
    def initialize(session:, device:, aes_key_hex:, lorenz_seed_hex: nil, ota_hmac_hex: nil, ed25519_seed_hex: nil, bcast_key_hex: nil,
                   probe_sn: nil, kv_journal_words: nil)
      @session = session
      @probe_sn = probe_sn
      @connect = self.class.connect(probe_sn)
      @device = device
      @aes_key_hex = aes_key_hex.to_s
      @lorenz_seed_hex = lorenz_seed_hex.to_s
      @ota_hmac_hex = ota_hmac_hex.to_s
      @ed25519_seed_hex = ed25519_seed_hex.to_s
      @bcast_key_hex = bcast_key_hex.to_s
      @kv_journal_words = kv_journal_words
      validate!
    end

    # Returns Array<String> — повний транскрипт: preflight + flash-тіло гілки.
    def commands
      self.class.preflight_commands(probe_sn: @probe_sn) + flash_commands
    end

    # [FW.54] Відкриття транскрипта обох гілок: connect + SWD-read кремнієвого
    # паспорта і першого слова сторінки ключів (магія KEYL — чи плата вже прошита:
    # для плати без паспорта від цього залежить, чи можна її стирати). Клас-метод
    # свідомо — не потребує ключів, тож Session ганяє його (і guard-и) ДО деривації
    # та будь-якого `-e`/`-w32`.
    def self.preflight_commands(probe_sn: nil)
      [ "#{PROGRAMMER} #{connect(probe_sn)} -r32 #{UID_BASE_ADDR} 12 -r32 #{FLASH_KEY_ADDR} 4" ]
    end

    def self.connect(probe_sn)
      return CONNECT if probe_sn.blank?
      raise ArgumentError, "probe_sn must be alphanumeric (ST-LINK serial)" unless probe_sn.match?(PROBE_SN)

      "#{CONNECT} sn=#{probe_sn}"
    end

    # Тіло гілки: стирання сторінок ключів + key-writes + IWDG-заморозка + RDP (без preflight).
    # [SE050-MIGRATION, ⚖️ делеговано 2026-09-27] Набір Protected-Flash-ключів
    # ОДИН для обох гілок: кожен із них має MCU-споживача (KEYL/KEYB — CRYP
    # радіо-AES, LSED — Lorenz-VM, K_ota — OTA-HMAC зі стор. 125), а SE за
    # SEC.14 лише ідентичність — його кроки емітить SecureElementProvisioner.
    # ⛔ Доти Гілка B SWD-ключів не писала зовсім: KEYL-less Солдат іде в
    # Error_Handler на першому boot, а Gilka-B Королева не мала навіть KEYC.
    def flash_commands
      raise ArgumentError, "Unknown gilka: #{@session.gilka.inspect}" unless %w[A B].include?(@session.gilka)

      protected_flash_commands
    end

    private

    def validate!
      raise ArgumentError, "aes_key_hex must be 32 or 64 hex chars" unless [ 32, 64 ].include?(@aes_key_hex.length)
      raise ArgumentError, "aes_key_hex must be hexadecimal" unless @aes_key_hex.match?(/\A[0-9A-Fa-f]+\z/)

      # [FW.2 (в)] Обидва типи й обидві гілки: без KEYB-значення транскрипт дає
      # або цеглу (Queen без KEYL), або Солдата, що в обох ерах не говорить із Королевою.
      raise ArgumentError, "bcast_key_hex is required (32 hex, FW.2 broadcast key)" unless @bcast_key_hex.length == 32
      raise ArgumentError, "bcast_key_hex must be hexadecimal" unless @bcast_key_hex.match?(/\A[0-9A-Fa-f]+\z/)

      if @ed25519_seed_hex.present?
        raise ArgumentError, "ed25519_seed_hex is Gateway-only (L1 QATT)" if @device.is_a?(Tree)
        raise ArgumentError, "ed25519_seed_hex must be 64 hex chars" unless @ed25519_seed_hex.length == 64
        raise ArgumentError, "ed25519_seed_hex must be hexadecimal" unless @ed25519_seed_hex.match?(/\A[0-9A-Fa-f]+\z/)
      end

      raise ArgumentError, "kv_journal_words is Tree-only (FW.17 re-provision)" if @kv_journal_words && !@device.is_a?(Tree)

      return unless @device.is_a?(Tree)
      raise ArgumentError, "Tree provisioning requires lorenz_seed_hex (64 hex)" unless @lorenz_seed_hex.length == 64
      raise ArgumentError, "lorenz_seed_hex must be hexadecimal" unless @lorenz_seed_hex.match?(/\A[0-9A-Fa-f]+\z/)
      raise ArgumentError, "Tree provisioning requires ota_hmac_hex (64 hex, FW.23 K_ota)" unless @ota_hmac_hex.length == 64
      raise ArgumentError, "ota_hmac_hex must be hexadecimal" unless @ota_hmac_hex.match?(/\A[0-9A-Fa-f]+\z/)
    end

    def protected_flash_commands
      words = {}

      if @device.is_a?(Tree)
        # Tree: 16-byte LoRa AES-128 key + 32-byte Lorenz K_seed + 32-byte K_ota.
        raise ArgumentError, "Tree requires 32-hex AES-128 key" unless @aes_key_hex.length == 32
        words.merge!(block_words(FLASH_KEY_ADDR, KEYL_MAGIC, @aes_key_hex))
        words.merge!(block_words(FLASH_SEED_ADDR, LSED_MAGIC, @lorenz_seed_hex))
        # [FW.23] K_ota — окрема сторінка 0x0803E800; без нього Load_Ota_Hmac_Key
        # лишає dual-gate fail-closed і жоден OTA не застосовується.
        words.merge!(block_words(FLASH_OTA_KEY_ADDR, KOTA_MAGIC, @ota_hmac_hex))
        # [FW.2 (в)] KEYB — cluster control-plane (та сама стор. 125, +40):
        # без нього Солдат (в обох ерах — з 2026-09-28 KEYB амбієнт і ECB-білда)
        # деградує у fallback (амбієнт = KEYL): Королева не прочитає його аплінк,
        # а він — її downlink.
        words.merge!(block_words(FLASH_BCAST_KEY_ADDR, KEYB_MAGIC, @bcast_key_hex))
        # [FW.17] Re-provision: свіжий журнал (лише 0x15), версії ратчета немає →
        # вузол на K0_e з v = 0 (03_05 §3.8).
        words.merge!(@kv_journal_words) if @kv_journal_words
      else
        # Gateway: 32-byte CoAP AES-256 key + LoRa KEYL = broadcast-значення
        # (FW.2 (в)): Королева шифрує ним downlink і читає 0x55/0x56; без
        # KEYL її Load_AES_Key() = Error_Handler → цегла на першому boot
        # (діра «LoRa slot intentionally unused» — закрито 2026-07-03).
        raise ArgumentError, "Gateway requires 64-hex AES-256 key" unless @aes_key_hex.length == 64
        words.merge!(block_words(FLASH_KEY_ADDR, KEYL_MAGIC, @bcast_key_hex))
        words.merge!(block_words(FLASH_COAP_KEY_ADDR, KEYC_MAGIC, @aes_key_hex))
        # [L1 QATT] Голос Королеви: сім'я підпису батчів. Відсутня → Queen
        # свідомо лишається на L0 (legacy-батчі без підпису).
        words.merge!(block_words(FLASH_EDSK_ADDR, EDSK_MAGIC, @ed25519_seed_hex)) if @ed25519_seed_hex.present?
      end

      erase_also = @kv_journal_words ? FlashKvImage::PAGES : []
      flash_write_commands(words, erase_also: erase_also) + [ iwdg_freeze_command, rdp_command(@session.rdp_level) ]
    end

    # Flash WL програмується лише цілим doubleword'ом (64 біти + 8 біт ECC —
    # stm32wlxx_hal_flash.c) і лише по стертому, а `-w32` сам не стирає
    # (STM32CubeProgrammer, примітка до `-w32`). Тож: стерти сторінки, яких
    # торкаємось (re-flash інакше впаде на першому ж записі; чистому чипу це no-op),
    # і писати кожен doubleword рівно раз — суміжні одним `-w32`, діру всередині
    # зачепленого добито стертим словом. Стирання незворотне: плату без паспорта
    # Session пускає сюди лише чистою або за REFLASH_ACK.
    # Сторінки виводяться з адрес запису: Королевина 125 (рантайм-OTA-SHA, FW.52)
    # і Солдатові 126 (mruby-контракт) сюди не потрапляють за побудовою.
    # `erase_also` — сторінки, які треба стерти, нічого в них не пишучи (сусідка
    # журналу при re-provision): «стерті» слова туди писати не можна — WL другого
    # програмування doubleword'а не приймає.
    def flash_write_commands(words, erase_also: [])
      dws = words.keys.map { |addr| addr & ~7 }.uniq.sort
      pages = (dws.map { |dw| (dw - FLASH_BASE) / FLASH_PAGE_SIZE } + erase_also).uniq.sort
      writes = dws.slice_when { |a, b| b != a + 8 }.map do |run|
        data = run.flat_map { |dw| [ words.fetch(dw, ERASED_WORD), words.fetch(dw + 4, ERASED_WORD) ] }
        "#{PROGRAMMER} #{@connect} -w32 #{format('0x%08X', run.first)} #{data.join(' ')}"
      end
      [ "#{PROGRAMMER} #{@connect} -e #{pages.join(' ')}" ] + writes
    end

    # [SEC.15] LSI-пес лічить і в STOP2 (max ~32.7 с), тож без `IWDG_STOP=0` Солдат
    # ресетиться посеред кожного багатогодинного сну — канон 03_01 §1.10. Пишеться ДО
    # RDP: на L2 option bytes стають read-only (03_05 §3.3), і незаморожений пес лишився б
    # таким назавжди. Королева в STOP2 не входить — для неї STOP/STDBY-біти інертні, а
    # `IWDG_SW=1` = її `MX_IWDG_Init`. Дзеркало: firmware/scripts/bench/01_option_bytes.sh.
    IWDG_FREEZE_OPTION_BYTES = "IWDG_SW=1 IWDG_STOP=0 IWDG_STDBY=0"

    def iwdg_freeze_command
      "#{PROGRAMMER} #{@connect} -ob #{IWDG_FREEZE_OPTION_BYTES}"
    end

    # { addr => "0x…" } — magic першим словом, далі payload по 4 байти.
    def block_words(base_addr, magic_word, payload_hex)
      base = Integer(base_addr, 16)
      words = [ magic_word ] + payload_hex.scan(/.{8}/).map { |w| "0x#{w.upcase}" }
      words.each_with_index.to_h { |word, i| [ base + i * 4, word ] }
    end

    # [SEC.2] `-ob RDP=` programs the RAW option byte, not a level number (UM2237:
    # «-ob [OptByte=<value>]: program the given option byte»). Bytes = ST's own
    # OB_RDP_LEVEL_0/1 (stm32wlxx_hal_flash.h); FLASH_OB_GetRDP decodes every value
    # but 0xAA/0xCC as Level 1, so a level NUMBER would lock L1. L2 (0xCC) the pipeline
    # never burns (⚖️ founder 2026-09-28): step 7 of 03_05 §3.6, after self-test and WRP.
    # Mirror of 0/1: firmware/scripts/bench/01_option_bytes.sh.
    RDP_OPTION_BYTE = { 0 => "0xAA", 1 => "0xBB" }.freeze

    def rdp_command(level)
      "#{PROGRAMMER} #{@connect} -ob RDP=#{RDP_OPTION_BYTE.fetch(level)}"
    end
  end
end
