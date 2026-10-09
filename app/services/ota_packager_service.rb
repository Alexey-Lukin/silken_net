# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "zlib"

class OtaPackagerService
  # Стандартні розміри для різних типів ефіру
  LORA_MTU = 11  # Для 16-байтних LoRa-пакетів (5 байтів заголовок: 1 маркер + 2 index + 2 total)
  COAP_MTU = 512 # Оптимально для Starlink/LTE

  # OTA / time-sync markers (docs/03_01 §4.5а). Адресні команди 0x9A · 0x9E
  # живуть у Downlink::CommandFrame (FW.17, 03_05 §2.5).
  CMD_OTA_BYTECODE   = 0x99 # mruby bytecode chunks (existing)
  CMD_OTA_SEAL       = 0x9B # [FW.23] OTA Ed25519 seal trailer (6 seal chunks + version)
  CMD_TIME_SYNC      = 0x9C # backend UTC timestamp envelope (FW.20)

  # ⚖️ [FW.23, founder 2026-10-05/06] Seal trailer — wire format mirrors
  # firmware/common/ota_seal_wire.h (the Soldier parses it, the Queen relays it blind).
  SEAL_SIG_BYTES       = 64  # Ed25519 signature R ‖ S
  SEAL_SEGMENTS        = 6   # 64 bytes across 6 LoRa chunks (seg_idx 1..6; the 6th = 9 bytes + 2 PAD)
  SEAL_VERSION_SEG_IDX = 7   # seg_idx=7 carries version_id (part of the signed message)
  OTA_TRAILER_CHUNKS   = 7   # 6 seal chunks + 1 version chunk
  SEAL_SEG_BYTES       = 11  # 11 bytes payload per LoRa chunk (16 - 5 header)

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

  # [FW.8] Тіло команди 0x9A для дерева — 8 Б:
  #   [z_min_x100:s16le][z_max_x100:s16le][z_opt_x100:s16le][species_id:u8][config_version:u8]
  # Пороги — з governance-ланцюга (cluster override > family > global,
  # Tree#effective_lorenz_thresholds). Кадр навколо тіла — CCM сесійним ключем
  # дерева (Downlink::CommandFrame.thresholds, 03_05 §2.5); len і CRC старого
  # каркаса зняла downlink-ревізія — цілісність несе MIC.
  def self.threshold_config_body(tree, config_version: 1)
    thresholds = tree.effective_lorenz_thresholds
    z_min   = (thresholds[:min]     * 100).round.to_i
    z_max   = (thresholds[:max]     * 100).round.to_i
    z_opt   = (thresholds[:optimal] * 100).round.to_i

    # tree_family — required belongs_to; unmapped scientific_name → DEFAULT
    species_id = SPECIES_ID_MAP[tree.tree_family.scientific_name] || DEFAULT_SPECIES_ID

    [ z_min, z_max, z_opt, species_id, config_version & 0xFF ].pack("s<s<s<CC")
  end

  # [FW.8] Смуга з x100-пари тіла 0x9A такою, якою її бачить пристрій: ціле
  # ділиться на 100.0 (`Lorenz_Band_Args`, common/lorenz_thresholds.h) — той самий
  # Float, що судить на кремнії. DCI читає смугу звідси, а не з
  # `effective_lorenz_thresholds`: родинне 5.004 їде на дріт як 500, тож пристрій
  # судить 5.0, і Z із [5.0, 5.004) розвело б два обчислення на чесному пакеті.
  def self.threshold_band(z_min_x100, z_max_x100)
    { min: z_min_x100 / 100.0, max: z_max_x100 / 100.0 }
  end

  # [FW.8] Class-level CRC16-CCITT (XMODEM polynomial 0x1021, init 0xFFFF)
  # Mirrored on firmware/queen/main.c:verify_crc16(). Exposed as class method so
  # FactoryFlashing::FlashKvImage (журнал Flash-KV) може кликати без інстансу сервісу.
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

  # [FW.23] The signed message: bytecode ‖ version_id_be(4) ‖ lora_total_be(2) — the
  # same bytes the HMAC covered before the seal became asymmetric.
  #   Anti-replay:     version_id binds the seal to a firmware revision.
  #   Anti-truncation: lora_total_chunks binds it to the EXACT chunk count the
  #                    Soldier expects — dropping trailing chunks breaks the seal.
  def self.seal_message(bytecode_bin, version_id, lora_total_chunks)
    raise ArgumentError, "bytecode is empty"          if bytecode_bin.nil? || bytecode_bin.bytesize.zero?
    raise ArgumentError, "version_id required"        if version_id.nil?
    raise ArgumentError, "lora_total_chunks required" if lora_total_chunks.nil? || lora_total_chunks.zero?

    bytecode_bin.b + [ version_id.to_i ].pack("N") + [ lora_total_chunks.to_i ].pack("n")
  end

  # ⚖️ [FW.23, founder 2026-10-05/06] Ed25519 seal of the cluster key (`OtaSealKeyService`).
  # DETERMINISTIC by construction (RFC 8032), and that is load-bearing: the campaign
  # package is prepared more than once (`Ota::PackageStore` packs at dispatch and again
  # when `GatewayStalenessSweepWorker` re-warms a missed cache) and the Queen relays whatever segments it
  # fetched — a randomised signature would stitch a trailer out of two different seals.
  # Returns the 64-byte signature; the Soldier verifies it with the cluster PUBLIC key only.
  def self.compute_seal(bytecode_bin, version_id, lora_total_chunks, cluster_id:)
    message = seal_message(bytecode_bin, version_id, lora_total_chunks)
    OtaSealKeyService.signing_key_for(cluster_id).sign(message)
  end

  # [FW.23] Build the 7 trailer 16-byte LoRa-formatted blocks: 6 carry the 64-byte seal,
  # the 7th carries version_id (part of the signed message — without it the Soldier has
  # nothing to verify against). Layout mirrors `Ota_Seal_Parse_Chunk`
  # (firmware/common/ota_seal_wire.h):
  #   [0]    0x9B (CMD_OTA_SEAL)
  #   [1..2] seg_idx (1..7, big-endian)
  #   [3..4] lora_total_chunks (big-endian) — signed; the Soldier accepts a seal block only
  #         with the total of its own assembly (FW.68), so a foreign trailer never lands
  #          (the signed total comes from the 0x99 headers — 00_07 FW.68)
  #   seg 1..6: [5..15] seal segment (11 bytes; seg 6 has 9 real bytes + 2 PAD)
  #   seg 7:    [5..8] version_id (big-endian) + [9..15] PAD
  # Deterministic for fixed (seal, lora_total_chunks, version_id).
  def self.build_seal_trailer_chunks(seal, lora_total_chunks, version_id)
    raise ArgumentError, "seal must be #{SEAL_SIG_BYTES} bytes" unless seal && seal.bytesize == SEAL_SIG_BYTES
    raise ArgumentError, "version_id required" if version_id.nil?

    chunks = Array.new(SEAL_SEGMENTS) do |i|
      slice = seal.byteslice(i * SEAL_SEG_BYTES, SEAL_SEG_BYTES)
      [ CMD_OTA_SEAL, i + 1, lora_total_chunks ].pack("Cnn") + slice.ljust(SEAL_SEG_BYTES, "\x00")
    end
    chunks << ([ CMD_OTA_SEAL, SEAL_VERSION_SEG_IDX, lora_total_chunks ].pack("Cnn") +
               [ version_id.to_i ].pack("N").ljust(SEAL_SEG_BYTES, "\x00"))
  end

  # [FW.53] LoRa MTU alignment + CRC32 trailer.
  # Soldier verifies the ASSEMBLED stream: its trailing 4 bytes must be the
  # big-endian CRC32 (ISO 3309 == Zlib.crc32) of everything before them —
  # this service previously never appended it, so every OTA died at the
  # Soldier's integrity gate. Soldier counts received bytes as 11 × chunks
  # (fixed LoRa MTU), so the CRC32 must land EXACTLY at the end of the final
  # 11-byte chunk: zero-pad the bytecode until (padded + 4) % 11 == 0.
  # Trailing zero-pad is harmless to the RITE loader (irep carries its own
  # length) and is covered by both CRC32 and the FW.23 seal.
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
      total_chunks: total_bytecode_chunks,
      lora_total_chunks: lora_total_chunks
    }
    return base unless sealed?

    # [FW.23] A sealed campaign exposes the (bytecode + trailer) package count. Its only
    # runtime reader is the superseded OtaTransmissionWorker (FW.60) — the live poll-tract
    # counts `packages.size` — so the field goes away together with that worker.
    base.merge(
      total_packages:    total_bytecode_chunks + OTA_TRAILER_CHUNKS,
      sealed:            true,
      seal_cluster_id:   @cluster_id
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

    return bytecode_chunks unless sealed?

    # [FW.23] Bytecode chunks + 7 trailer chunks (6 seal + 1 version). Trailer chunks
    # are 16-byte LoRa-pre-formatted blocks the Queen relays as-is; the Soldier checks
    # the seal before the flash write.
    Enumerator.new do |yielder|
      bytecode_chunks.each { |bc| yielder.yield(bc) }
      seal_trailer_chunks.each { |tc| yielder.yield(tc) }
    end
  end

  def sealed?
    @cluster_id.present?
  end

  # [FW.53] LoRa-чанки рахуються від WIRE-потоку (padded +
  # CRC32) — він за конструкцією кратний LORA_MTU, тож ділення точне. Саме
  # це число Queen виводить з pending_ota_size і Soldier тримає як
  # ota_total_chunks (cross-check у re-request + у підписаному повідомленні печатки).
  def lora_total_chunks
    @lora_total_chunks ||= (@wire_payload.bytesize / LORA_MTU)
  end

  def seal_trailer_chunks
    # Печатка над padded bytecode (БЕЗ CRC32-хвоста) — дзеркало Солдата, що перевіряє
    # ota_buffer[0..data_len) після зрізання CRC (`Ota_Seal_Try_Finalize`).
    seal = self.class.compute_seal(@padded_payload, @firmware.id, lora_total_chunks, cluster_id: @cluster_id)
    self.class.build_seal_trailer_chunks(seal, lora_total_chunks, @firmware.id)
  end
end
