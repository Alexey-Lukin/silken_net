# frozen_string_literal: true

# [SEC.3] Factory Flashing — STM32CubeProgrammer CLI command emission.
#
# Generates the canonical sequence of `STM32_Programmer_CLI` invocations that
# burn a per-device key payload into the Protected Flash Sector and lock the
# chip. The flash layout MUST match firmware constants
# (firmware/soldier/main.c §FLASH_KEY_ADDR — post-ARCH.42):
#
#   0x0803E000  [magic "KEYL" :4 ][ aes_lora_key :16 ]
#   0x0803E014  [magic "LSED" :4 ][ k_seed       :32 ]                 # Tree only
#   0x0803Exxx  [magic "KEYC" :4 ][ aes_coap_key :32 ]                 # Gateway only
#
# Output is an Array<String> — one shell command per element. Callers pipe it
# through Executor (dry-run prints to stdout; --execute spawns subprocesses).
module FactoryFlashing
  class CommandBuilder
    FLASH_KEY_ADDR      = "0x0803E000"
    FLASH_SEED_ADDR     = "0x0803E014"   # FLASH_KEY_ADDR + 4 (magic) + 16 (key)
    FLASH_COAP_KEY_ADDR = "0x0803E040"   # After K_seed (4 magic + 32 = 36 bytes) — see Queen flash layout

    KEYL_MAGIC = "0x4B45594C" # "KEYL" LoRa key magic (firmware: FLASH_KEY_MAGIC)
    LSED_MAGIC = "0x4C534544" # "LSED" Lorenz K_seed magic (firmware: FLASH_SEED_MAGIC)
    KEYC_MAGIC = "0x4B455943" # "KEYC" CoAP key magic (firmware: FLASH_COAP_KEY_MAGIC)

    PROGRAMMER = "STM32_Programmer_CLI"

    # @param session   [ProvisioningSession]
    # @param device    [Tree|Gateway]
    # @param aes_key_hex     [String] 32 hex (Tree LoRa) or 64 hex (Gateway CoAP)
    # @param lorenz_seed_hex [String, nil] 64 hex; required for Tree
    def initialize(session:, device:, aes_key_hex:, lorenz_seed_hex: nil)
      @session = session
      @device = device
      @aes_key_hex = aes_key_hex.to_s
      @lorenz_seed_hex = lorenz_seed_hex.to_s
      validate!
    end

    # Returns Array<String> — ordered shell commands.
    def commands
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
      return unless @device.is_a?(Tree)
      raise ArgumentError, "Tree provisioning requires lorenz_seed_hex (64 hex)" unless @lorenz_seed_hex.length == 64
      raise ArgumentError, "lorenz_seed_hex must be hexadecimal" unless @lorenz_seed_hex.match?(/\A[0-9A-Fa-f]+\z/)
    end

    def gilka_a_commands
      out = [ connect_command ]

      if @device.is_a?(Tree)
        # Tree: 16-byte LoRa AES-128 key + 32-byte Lorenz K_seed.
        raise ArgumentError, "Tree requires 32-hex AES-128 key" unless @aes_key_hex.length == 32
        out.concat(write_block(FLASH_KEY_ADDR, KEYL_MAGIC, @aes_key_hex))
        out.concat(write_block(FLASH_SEED_ADDR, LSED_MAGIC, @lorenz_seed_hex))
      else
        # Gateway: 32-byte CoAP AES-256 key. LoRa AES-128 slot intentionally
        # unused (CoAP only); firmware loads coap_key from FLASH_COAP_KEY_ADDR.
        raise ArgumentError, "Gateway requires 64-hex AES-256 key" unless @aes_key_hex.length == 64
        out.concat(write_block(FLASH_COAP_KEY_ADDR, KEYC_MAGIC, @aes_key_hex))
      end

      out << rdp_command(@session.rdp_level)
      out << disconnect_command
      out
    end

    def gilka_b_commands
      # Гілка B routes the key through I²C ATCA write-zone instead of SWD writes.
      # AteccProvisioner emits those statements; CommandBuilder only handles
      # the surrounding STM32 firmware-flash + RDP-lock pair. The intermediate
      # ATCA sequence is appended by Session#run via AteccProvisioner.
      [
        connect_command,
        # No SWD key writes — keys live in ATECC608B data zone.
        rdp_command(@session.rdp_level),
        disconnect_command
      ]
    end

    def connect_command
      "#{PROGRAMMER} -c port=SWD reset=HWrst"
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
