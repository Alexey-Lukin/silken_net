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
    # @param bcast_key_hex [String, nil] 32 hex; required Гілка A (обидва
    #   типи) — FW.2 (в) cluster control-plane ключ (derive_broadcast_key):
    #   Tree → KEYB-слот, Gateway → її KEYL-слот (без нього Королева цеглиться
    #   на boot, а Солдат CCM-ери глухне до downlink'а).
    def initialize(session:, device:, aes_key_hex:, lorenz_seed_hex: nil, ota_hmac_hex: nil, ed25519_seed_hex: nil, bcast_key_hex: nil)
      @session = session
      @device = device
      @aes_key_hex = aes_key_hex.to_s
      @lorenz_seed_hex = lorenz_seed_hex.to_s
      @ota_hmac_hex = ota_hmac_hex.to_s
      @ed25519_seed_hex = ed25519_seed_hex.to_s
      @bcast_key_hex = bcast_key_hex.to_s
      validate!
    end

    # Returns Array<String> — повний транскрипт: preflight + flash-тіло гілки.
    def commands
      self.class.preflight_commands + flash_commands
    end

    # [FW.54] Відкриття транскрипта обох гілок: connect + SWD-read кремнієвого
    # паспорта. Клас-метод свідомо — не потребує ключів, тож Session ганяє
    # його (і wrong-board guard) ДО деривації та будь-якого -w32.
    def self.preflight_commands
      [
        "#{PROGRAMMER} -c port=SWD reset=HWrst",
        "#{PROGRAMMER} -r32 #{UID_BASE_ADDR} 12"
      ]
    end

    # Тіло гілки: key-writes + RDP + disconnect (без preflight).
    def flash_commands
      case @session.gilka
      when "A" then gilka_a_commands
      when "B" then gilka_b_commands
      else
        raise ArgumentError, "Unknown gilka: #{@session.gilka.inspect}"
      end
    end

    private

    def validate!
      raise ArgumentError, "aes_key_hex must be 32 or 64 hex chars" unless [ 32, 64 ].include?(@aes_key_hex.length)
      raise ArgumentError, "aes_key_hex must be hexadecimal" unless @aes_key_hex.match?(/\A[0-9A-Fa-f]+\z/)

      if @session.gilka == "A"
        # [FW.2 (в)] Обидва типи: без KEYB-значення транскрипт дає або цеглу
        # (Queen без KEYL), або downlink-глухого Солдата в CCM-еру.
        raise ArgumentError, "bcast_key_hex is required for Gilka A (32 hex, FW.2 broadcast key)" unless @bcast_key_hex.length == 32
        raise ArgumentError, "bcast_key_hex must be hexadecimal" unless @bcast_key_hex.match?(/\A[0-9A-Fa-f]+\z/)
      end

      if @ed25519_seed_hex.present?
        raise ArgumentError, "ed25519_seed_hex is Gateway-only (L1 QATT)" if @device.is_a?(Tree)
        raise ArgumentError, "ed25519_seed_hex must be 64 hex chars" unless @ed25519_seed_hex.length == 64
        raise ArgumentError, "ed25519_seed_hex must be hexadecimal" unless @ed25519_seed_hex.match?(/\A[0-9A-Fa-f]+\z/)
      end

      return unless @device.is_a?(Tree)
      raise ArgumentError, "Tree provisioning requires lorenz_seed_hex (64 hex)" unless @lorenz_seed_hex.length == 64
      raise ArgumentError, "lorenz_seed_hex must be hexadecimal" unless @lorenz_seed_hex.match?(/\A[0-9A-Fa-f]+\z/)
      return unless @session.gilka == "A" # Гілка B: ключі пише SE-provisioner, не SWD
      raise ArgumentError, "Tree provisioning requires ota_hmac_hex (64 hex, FW.23 K_ota)" unless @ota_hmac_hex.length == 64
      raise ArgumentError, "ota_hmac_hex must be hexadecimal" unless @ota_hmac_hex.match?(/\A[0-9A-Fa-f]+\z/)
    end

    def gilka_a_commands
      out = []

      if @device.is_a?(Tree)
        # Tree: 16-byte LoRa AES-128 key + 32-byte Lorenz K_seed + 32-byte K_ota.
        raise ArgumentError, "Tree requires 32-hex AES-128 key" unless @aes_key_hex.length == 32
        out.concat(write_block(FLASH_KEY_ADDR, KEYL_MAGIC, @aes_key_hex))
        out.concat(write_block(FLASH_SEED_ADDR, LSED_MAGIC, @lorenz_seed_hex))
        # [FW.23] K_ota — окрема сторінка 0x0803E800; без нього Load_Ota_Hmac_Key
        # лишає dual-gate fail-closed і жоден OTA не застосовується.
        out.concat(write_block(FLASH_OTA_KEY_ADDR, KOTA_MAGIC, @ota_hmac_hex))
        # [FW.2 (в)] KEYB — cluster control-plane (та сама стор. 125, +40):
        # без нього Солдат CCM-ери деградує у fallback (амбієнт = KEYL) і
        # downlink Королеви для нього нечитний.
        out.concat(write_block(FLASH_BCAST_KEY_ADDR, KEYB_MAGIC, @bcast_key_hex))
      else
        # Gateway: 32-byte CoAP AES-256 key + LoRa KEYL = broadcast-значення
        # (FW.2 (в)): Королева шифрує ним downlink і читає 0x55/0x56; без
        # KEYL її Load_AES_Key() = Error_Handler → цегла на першому boot
        # (діра «LoRa slot intentionally unused» — закрито 2026-07-03).
        raise ArgumentError, "Gateway requires 64-hex AES-256 key" unless @aes_key_hex.length == 64
        out.concat(write_block(FLASH_KEY_ADDR, KEYL_MAGIC, @bcast_key_hex))
        out.concat(write_block(FLASH_COAP_KEY_ADDR, KEYC_MAGIC, @aes_key_hex))
        # [L1 QATT] Голос Королеви: сім'я підпису батчів. Відсутня → Queen
        # свідомо лишається на L0 (legacy-батчі без підпису).
        out.concat(write_block(FLASH_EDSK_ADDR, EDSK_MAGIC, @ed25519_seed_hex)) if @ed25519_seed_hex.present?
      end

      out << rdp_command(@session.rdp_level)
      out << disconnect_command
      out
    end

    def gilka_b_commands
      # Гілка B routes the key through I²C ATCA write-zone instead of SWD writes.
      # AteccProvisioner emits those statements; CommandBuilder only handles
      # the surrounding RDP-lock pair (connect живе у preflight_commands).
      [
        # No SWD key writes — keys live in ATECC608B data zone.
        rdp_command(@session.rdp_level),
        disconnect_command
      ]
    end

    def disconnect_command
      "#{PROGRAMMER} -c port=SWD --quietMode"
    end

    # Returns Array<String> — `-w32 <addr> <hex_word>` per word, magic first.
    def write_block(base_addr, magic_word, payload_hex)
      base = Integer(base_addr, 16)
      words = [ magic_word ] + payload_hex.scan(/.{8}/).map { |w| "0x#{w.upcase}" }
      words.each_with_index.map do |word, i|
        addr = format("0x%08X", base + i * 4)
        "#{PROGRAMMER} -w32 #{addr} #{word}"
      end
    end

    def rdp_command(level)
      "#{PROGRAMMER} -ob RDP=#{level}"
    end
  end
end
