# SPDX-License-Identifier: AGPL-3.0-or-later
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
  CMD_ROTATE_KEY     = 0x9E # [FW.17] hash-ratchet advance-to-version (без ключа на дроті)

  # [FW.23] HMAC trailer constants — wire format must mirror Soldier parser.
  HMAC_TAG_BYTES        = 32   # HMAC-SHA256 output size
  HMAC_TRAILER_SEGMENTS = 3    # 32 bytes split across 3 LoRa chunks (seg_idx 1..3)
  HMAC_VERSION_SEG_IDX  = 4    # seg_idx=4 carries version_id (Soldier HMAC input)
  OTA_TRAILER_CHUNKS    = 4    # 3 HMAC tag chunks + 1 version chunk
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

    # tree_family — required belongs_to; unmapped scientific_name → DEFAULT
    species_id = SPECIES_ID_MAP[tree.tree_family.scientific_name] || DEFAULT_SPECIES_ID
    version    = (config_version & 0xFF)

    body = [ z_min, z_max, z_opt, species_id, version ].pack("s<s<s<CC")
    crc  = crc16_ccitt(body)
    payload = body + [ crc ].pack("v") # uint16 little-endian

    [ CMD_SET_THRESHOLDS ].pack("C") + [ payload.bytesize ].pack("v") + payload
  end

  # [FW.17] Build a CMD_ROTATE_KEY (0x9E) frame — каркас 0x9A, але body = лише
  # target_version: ключ НІКОЛИ не їде дротом, пристрій деривує його сам
  # (Cryptography::KeyRatchet ↔ firmware/common/key_ratchet.h).
  # Wire: [0x9E][PAYLOAD_LEN:2le = 4][target_version:u16le][crc16:u16le] = 7 байт.
  def self.build_rotate_key_block(target_version)
    raise ArgumentError, "target_version must be 1..65535" unless (1..0xFFFF).cover?(target_version)

    body = [ target_version ].pack("v")
    payload = body + [ crc16_ccitt(body) ].pack("v")
    [ CMD_ROTATE_KEY ].pack("C") + [ payload.bytesize ].pack("v") + payload
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

  # [FW.23] Build 4 trailer 16-byte LoRa-formatted blocks. The first 3 carry the
  # 32-byte HMAC tag; the 4th carries version_id so the Soldier can recompute the
  # HMAC over (bytecode ‖ version_id_be ‖ total_be) — without it the dual-gate has
  # no version input on the wire and stays inert. Layout mirrors Soldier
  # `Parse_HMAC_Trailer_Chunk`:
  #   [0]    0x9B (CMD_HMAC_TRAILER)
  #   [1..2] seg_idx (1..4, big-endian)
  #   [3..4] lora_total_chunks (big-endian) — cross-check vs bytecode 0x99 header
  #   seg 1..3: [5..15] hmac segment (11 bytes; seg=3 has 10 real bytes + 1 PAD)
  #   seg 4:    [5..8] version_id (big-endian) + [9..15] PAD
  #
  # Deterministic for fixed (hmac_tag, lora_total_chunks, version_id).
  def self.build_hmac_trailer_chunks(hmac_tag, lora_total_chunks, version_id)
    raise ArgumentError, "hmac_tag must be #{HMAC_TAG_BYTES} bytes" \
      unless hmac_tag && hmac_tag.bytesize == HMAC_TAG_BYTES
    raise ArgumentError, "version_id required" if version_id.nil?

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

    # seg 4 — version envelope. version_id binds the tag to a firmware revision;
    # the same 4-byte BE value goes into compute_hmac_tag's HMAC input.
    version_header = [ CMD_HMAC_TRAILER, HMAC_VERSION_SEG_IDX, lora_total_chunks ].pack("Cnn")
    version_body   = [ version_id.to_i ].pack("N") + ("\x00" * (HMAC_SEG_BYTES - 4))
    chunks << (version_header + version_body)
    chunks
  end

  # [FW.53] LoRa MTU alignment + CRC32 trailer.
  # Soldier verifies the ASSEMBLED stream: its trailing 4 bytes must be the
  # big-endian CRC32 (ISO 3309 == Zlib.crc32) of everything before them —
  # this service previously never appended it, so every OTA died at the
  # Soldier's integrity gate. Soldier counts received bytes as 11 × chunks
  # (fixed LoRa MTU), so the CRC32 must land EXACTLY at the end of the final
  # 11-byte chunk: zero-pad the bytecode until (padded + 4) % 11 == 0.
  # Trailing zero-pad is harmless to the RITE loader (irep carries its own
  # length) and is covered by both CRC32 and the FW.23 HMAC tag.
  LORA_CRC32_BYTES = 4

  def initialize(firmware, chunk_size, cluster_id: nil)
    @firmware = firmware
    @chunk_size = chunk_size
    @payload = firmware.binary_payload
    @cluster_id = cluster_id

    pad_len = (LORA_MTU - ((@payload.bytesize + LORA_CRC32_BYTES) % LORA_MTU)) % LORA_MTU
    @padded_payload = @payload.b + ("\x00".b * pad_len)
    @wire_payload   = @padded_payload + [ Zlib.crc32(@padded_payload) ].pack("N")
  end

  def prepare
    {
      manifest: generate_manifest,
      packages: generate_packages
    }
  end

  private

  # Маніфест для перевірки всієї прошивки після збірки на пристрої.
  # total_chunks / lora_total_chunks рахуються від WIRE-потоку
  # (padded bytecode + CRC32), бо саме його чанкують CoAP та LoRa шари.
  def generate_manifest
    total_bytecode_chunks = (@wire_payload.bytesize.to_f / @chunk_size).ceil
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
      total_packages:    total_bytecode_chunks + OTA_TRAILER_CHUNKS,
      hmac_signed:       true,
      hmac_cluster_id:   @cluster_id
    )
  end

  def generate_packages
    total = (@wire_payload.bytesize.to_f / @chunk_size).ceil
    payload_bytes = @wire_payload

    bytecode_chunks = Enumerator.new do |yielder|
      payload_bytes.scan(/.{1,#{@chunk_size}}/m).each_with_index do |chunk, index|
        # [FW.53] Заголовок несе ЯВНИЙ len (uint16 BE):
        # Queen більше не вгадує довжину з CBC zero-padding (стара формула
        # обрізала 1..16 байт кожного чанка). Дзеркало парсера —
        # firmware/queen/main.c Handle_CoAP_Command (0x99 branch).
        header = [
          CMD_OTA_BYTECODE, # OTA Marker (0x99)
          index,            # Chunk Index   (uint16 big-endian)
          total,            # Total Chunks  (uint16 big-endian)
          chunk.bytesize    # Payload Len   (uint16 big-endian)
        ].pack("Cnnn")

        # CRC16 над header+chunk — Queen тепер ПЕРЕВІРЯЄ його перед збіркою
        package_payload = header + chunk
        crc = self.class.crc16_ccitt(package_payload)
        yielder.yield(package_payload + [ crc ].pack("n"))
      end
    end

    return bytecode_chunks unless hmac_enabled?

    # [FW.23] Concatenate bytecode chunks + 4 trailer chunks (3 HMAC + 1 version).
    # Worker iterates packages.to_a; trailer chunks are 16-byte LoRa-pre-formatted
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

  # [FW.53] LoRa-чанки рахуються від WIRE-потоку (padded +
  # CRC32) — він за конструкцією кратний LORA_MTU, тож ділення точне. Саме
  # це число Queen виводить з pending_ota_size і Soldier тримає як
  # ota_total_chunks (cross-check у re-request + HMAC binding).
  def lora_total_chunks
    @lora_total_chunks ||= (@wire_payload.bytesize / LORA_MTU)
  end

  def hmac_trailer_chunks
    # HMAC над padded bytecode (БЕЗ CRC32-хвоста) — дзеркало Soldier
    # dual-gate, який хешує ota_buffer[0..data_len) після зрізання CRC.
    tag = self.class.compute_hmac_tag(
      @padded_payload,
      @firmware.id,
      lora_total_chunks,
      cluster_id: @cluster_id
    )
    self.class.build_hmac_trailer_chunks(tag, lora_total_chunks, @firmware.id)
  end
end
