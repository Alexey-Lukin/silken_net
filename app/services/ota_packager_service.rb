# frozen_string_literal: true

require "zlib"

class OtaPackagerService
  # Стандартні розміри для різних типів ефіру
  LORA_MTU = 11  # Для 16-байтних LoRa-пакетів (5 байтів заголовок: 1 маркер + 2 index + 2 total)
  COAP_MTU = 512 # Оптимально для Starlink/LTE

  # [FW.8] OTA Config Payload command markers (per docs/05_02 §4а.1)
  CMD_OTA_BYTECODE   = 0x99 # mruby bytecode chunks (existing)
  CMD_SET_THRESHOLDS = 0x9A # per-tree Lorenz Z thresholds
  CMD_TIME_SYNC      = 0x9C # backend UTC timestamp envelope (FW.20)

  # [FW.8] Default species_id when tree.tree_family.species_code is unmapped
  DEFAULT_SPECIES_ID = 0xFF

  # [FW.8] Map of tree_family.scientific_name → species_id byte sent to firmware.
  # Firmware uses species_id only as a hint for log/observability; thresholds are
  # the source of truth.
  SPECIES_ID_MAP = {
    "Pinus sylvestris" => 0,
    "Quercus robur"    => 1,
    "Fagus sylvatica"  => 2,
    "Picea abies"      => 3,
    "Betula pendula"   => 4
  }.freeze

  def self.prepare(firmware, chunk_size: COAP_MTU)
    new(firmware, chunk_size).prepare
  end

  # [FW.8] Build a CMD_SET_THRESHOLDS (0x9A) OTA config block for the given Tree.
  # Wire format (per docs/05_02 §4а.1):
  #   [CMD_TYPE:1=0x9A] [PAYLOAD_LEN:2 little-endian] [PAYLOAD:10]
  #   PAYLOAD = [z_min_x100:int16le][z_max_x100:int16le][z_opt_x100:int16le]
  #             [species_id:u8][config_version:u8][crc16:u16le over bytes 0..7]
  # Returns binary String (13 bytes total).
  def self.build_threshold_config_block(tree, config_version: 1)
    thresholds = tree.effective_lorenz_thresholds
    z_min   = (thresholds[:min]     * 100).round.to_i
    z_max   = (thresholds[:max]     * 100).round.to_i
    z_opt   = (thresholds[:optimal] * 100).round.to_i

    species_id = SPECIES_ID_MAP[tree.tree_family&.scientific_name] || DEFAULT_SPECIES_ID
    version    = (config_version & 0xFF)

    body = [ z_min, z_max, z_opt, species_id, version ].pack("s<s<s<CC")
    crc  = crc16_ccitt(body)
    payload = body + [ crc ].pack("v") # uint16 little-endian

    [ CMD_SET_THRESHOLDS ].pack("C") + [ payload.bytesize ].pack("v") + payload
  end

  # [FW.8] Class-level CRC16-CCITT (XMODEM polynomial 0x1021, init 0xFFFF)
  # Mirrored on firmware/queen/main.c:verify_crc16(). Exposed as class method so
  # build_threshold_config_block can be called without instantiating the service.
  def self.crc16_ccitt(data)
    crc = 0xFFFF
    data.each_byte do |byte|
      crc ^= byte << 8
      8.times do
        crc = (crc & 0x8000).nonzero? ? (crc << 1) ^ 0x1021 : crc << 1
        crc &= 0xFFFF
      end
    end
    crc
  end

  def initialize(firmware, chunk_size)
    @firmware = firmware
    @chunk_size = chunk_size
    @payload = firmware.binary_payload #
  end

  def prepare
    {
      manifest: generate_manifest,
      packages: generate_packages
    }
  end

  private

  # Маніфест для перевірки всієї прошивки після збірки на пристрої
  def generate_manifest
    {
      version: @firmware.version,
      total_size: @payload.bytesize,
      checksum: Zlib.crc32(@payload).to_s(16).upcase,
      sha256: @firmware.binary_sha256,
      total_chunks: (@payload.bytesize.to_f / @chunk_size).ceil
    }
  end

  def generate_packages
    total = (@payload.bytesize.to_f / @chunk_size).ceil
    payload_bytes = @payload.b

    Enumerator.new do |yielder|
      payload_bytes.scan(/.{1,#{@chunk_size}}/m).each_with_index do |chunk, index|
        # Формуємо заголовок загартованого пакета (16-bit index/total для підтримки >255 чанків)
        header = [
          CMD_OTA_BYTECODE, # OTA Marker (0x99)
          index,            # Chunk Index   (uint16 big-endian)
          total             # Total Chunks  (uint16 big-endian)
        ].pack("Cnn")

        # Додаємо CRC16 для кожного чанка для Zero-Lag валідації на рівні заліза
        package_payload = header + chunk
        crc = self.class.crc16_ccitt(package_payload)
        yielder.yield(package_payload + [ crc ].pack("n"))
      end
    end
  end
end
