# frozen_string_literal: true

require "zlib"
require "openssl"

class OtaPackagerService
  # Стандартні розміри для різних типів ефіру
  LORA_MTU = 11  # Для 16-байтних LoRa-пакетів (5 байтів заголовок: 1 маркер + 2 index + 2 total)
  COAP_MTU = 512 # Оптимально для Starlink/LTE

  # [FW.8] OTA Config Payload command markers (per docs/05_02 §4а.1)
  CMD_OTA_BYTECODE   = 0x99 # mruby bytecode chunks (existing)
  CMD_SET_THRESHOLDS = 0x9A # per-tree Lorenz Z thresholds
  CMD_HMAC_TRAILER   = 0x9B # [FW.23] OTA HMAC-SHA256 trailer (3 LoRa chunks)
  CMD_TIME_SYNC      = 0x9C # backend UTC timestamp envelope (FW.20)

  # [FW.23] HMAC trailer constants — wire format must mirror Soldier parser.
  HMAC_TAG_BYTES        = 32   # HMAC-SHA256 output size
  HMAC_TRAILER_SEGMENTS = 3    # 32 bytes split across 3 LoRa chunks
  HMAC_SEG_BYTES        = 11   # 11 bytes payload per LoRa chunk (16 - 5 header)
  HMAC_TRAILER_BLOCK    = 16   # Single AES-256 block size on the wire

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

  def self.prepare(firmware, chunk_size: COAP_MTU, cluster_id: nil)
    new(firmware, chunk_size, cluster_id: cluster_id).prepare
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

  # [FW.23] Compute HMAC-SHA256 over (bytecode || version_id_be || lora_total_be).
  #
  # Anti-replay:    version_id binds the tag to a specific firmware revision so
  #                 an attacker cannot replay an old (signed) image.
  # Anti-truncation: lora_total_chunks binds the tag to the EXACT chunk count
  #                  Soldier expects to receive — dropping trailing chunks is
  #                  detected as HMAC mismatch.
  #
  # Returns 32-byte binary digest. Soldier dual-gate uses constant-time compare.
  def self.compute_hmac_tag(bytecode_bin, version_id, lora_total_chunks, cluster_id:)
    raise ArgumentError, "bytecode is empty"         if bytecode_bin.nil? || bytecode_bin.bytesize.zero?
    raise ArgumentError, "version_id required"       if version_id.nil?
    raise ArgumentError, "lora_total_chunks required" if lora_total_chunks.nil? || lora_total_chunks.zero?

    binary_key = OtaHmacKeyService.fetch_binary_for(cluster_id)
    message    = bytecode_bin.b +
                 [ version_id.to_i ].pack("N") +       # 4-byte big-endian
                 [ lora_total_chunks.to_i ].pack("n")  # 2-byte big-endian
    OpenSSL::HMAC.digest("SHA256", binary_key, message)
  end

  # [FW.23] Build 3 trailer 16-byte LoRa-formatted blocks carrying the 32-byte
  # HMAC tag. Each block layout matches Soldier `Parse_HMAC_Trailer_Chunk`:
  #   [0]    0x9B (CMD_HMAC_TRAILER)
  #   [1..2] seg_idx (1..3, big-endian)
  #   [3..4] lora_total_chunks (big-endian) — cross-check vs bytecode 0x99 header
  #   [5..15] hmac segment (11 bytes; seg=3 has 10 real bytes + 1 PAD)
  #
  # Deterministic for fixed (hmac_tag, lora_total_chunks).
  def self.build_hmac_trailer_chunks(hmac_tag, lora_total_chunks)
    raise ArgumentError, "hmac_tag must be #{HMAC_TAG_BYTES} bytes" \
      unless hmac_tag && hmac_tag.bytesize == HMAC_TAG_BYTES

    chunks = []
    HMAC_TRAILER_SEGMENTS.times do |i|
      seg_idx = i + 1
      base    = i * HMAC_SEG_BYTES
      slice   = hmac_tag.byteslice(base, HMAC_SEG_BYTES) || ""
      # Last segment may be < 11 bytes (32 - 22 = 10) → pad to 11 with NUL.
      slice = slice + ("\x00" * (HMAC_SEG_BYTES - slice.bytesize)) if slice.bytesize < HMAC_SEG_BYTES

      header = [ CMD_HMAC_TRAILER, seg_idx, lora_total_chunks ].pack("Cnn")
      chunks << (header + slice)
    end
    chunks
  end

  def initialize(firmware, chunk_size, cluster_id: nil)
    @firmware = firmware
    @chunk_size = chunk_size
    @payload = firmware.binary_payload
    @cluster_id = cluster_id
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
    total_bytecode_chunks = (@payload.bytesize.to_f / @chunk_size).ceil
    base = {
      version: @firmware.version,
      total_size: @payload.bytesize,
      checksum: Zlib.crc32(@payload).to_s(16).upcase,
      sha256: @firmware.binary_sha256,
      total_chunks: total_bytecode_chunks
    }
    return base unless hmac_enabled?

    # [FW.23] When HMAC trailer is enabled, expose extra metadata so the
    # OtaTransmissionWorker can iterate over (bytecode + 3 trailer) packages
    # without re-counting and so the UI progress bar stays correct.
    base.merge(
      lora_total_chunks: lora_total_chunks,
      total_packages:    total_bytecode_chunks + HMAC_TRAILER_SEGMENTS,
      hmac_signed:       true,
      hmac_cluster_id:   @cluster_id
    )
  end

  def generate_packages
    total = (@payload.bytesize.to_f / @chunk_size).ceil
    payload_bytes = @payload.b

    bytecode_chunks = Enumerator.new do |yielder|
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

    return bytecode_chunks unless hmac_enabled?

    # [FW.23] Concatenate bytecode chunks + 3 HMAC trailer chunks. Worker
    # iterates packages.to_a; trailer chunks are 16-byte LoRa-pre-formatted
    # blocks that Queen relays directly (stateless) and Soldier verifies via
    # dual-gate before flash write.
    Enumerator.new do |yielder|
      bytecode_chunks.each { |bc| yielder.yield(bc) }
      hmac_trailer_chunks.each { |tc| yielder.yield(tc) }
    end
  end

  def hmac_enabled?
    @cluster_id.present?
  end

  def lora_total_chunks
    @lora_total_chunks ||= ((@payload.bytesize + LORA_MTU - 1) / LORA_MTU)
  end

  def hmac_trailer_chunks
    tag = self.class.compute_hmac_tag(
      @payload,
      @firmware.id,
      lora_total_chunks,
      cluster_id: @cluster_id
    )
    self.class.build_hmac_trailer_chunks(tag, lora_total_chunks)
  end
end
