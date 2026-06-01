# frozen_string_literal: true

# Shared builders for binary telemetry chunks used by uplink specs.
#
# Auto-included for specs whose path matches `spec/**/*telemetry*` —
# currently the TelemetryUnpackerService unit spec, the integration
# pipeline spec, and any future telemetry-adjacent worker / model specs
# (e.g. FW.45 fixed-point Q-format).
#
# Why these helpers live in spec/support:
#
#   * Three near-identical `build_chunk` copies had drifted between
#     `spec/services/telemetry_unpacker_service_spec.rb` and
#     `spec/integration/telemetry_ingestion_pipeline_spec.rb` —
#     this is the canonical implementation.
#   * `build_ccm_chunk` was inlined inside one describe-block, blocking
#     reuse from `unpack_telemetry_worker_spec` and any future CCM
#     consumer (Streamr broadcaster spec, dual-write integration spec).
#   * Centralising the wire-format keeps changes in lockstep with
#     `TelemetryUnpackerService::PAYLOAD_FORMAT` / `CCM_SENSOR_PAYLOAD_FORMAT`
#     and the firmware specs in `docs/03_04` / `03_05`.
#
# All helpers return binary strings in ASCII-8BIT — pass them straight
# to `TelemetryUnpackerService.call` (or feed into `binary_batch` slots).
#
module TelemetryChunkHelper
  extend ActiveSupport::Concern

  # ---------------------------------------------------------------------
  # 21-byte AES-128-ECB chunk (legacy / pre-FW.2 wire format).
  #
  #   [DID:4][RSSI:1][Payload:16]
  #   Payload format: "N n c C n C C a4"
  #     DID(4), voltage_mv(2), temp_c(1), acoustic(1), metabolism_s(2),
  #     status_byte(1), ttl(1), pad(4)
  #
  # `rssi` is supplied in real dBm units (e.g. -70). Firmware stores the
  # absolute value as uint8 and the service inverts on decode — this
  # helper matches that convention so callers can pass `-70` directly.
  # ---------------------------------------------------------------------
  def build_chunk(did_hex, rssi, voltage, temp, acoustic, metabolism, status_byte, ttl,
                  pad = "\x00\x00\x00\x00")
    did_int   = did_hex.to_i(16)
    header    = [ did_int ].pack("N")
    rssi_byte = [ -rssi ].pack("C")
    payload   = [ did_int, voltage, temp, acoustic, metabolism, status_byte, ttl, pad ]
                  .pack("N n c C n C C a4")
    header + rssi_byte + payload
  end

  # Keyword variant used by the "edge cases from coverage enhancement"
  # describe-block. `firmware_id` is packed into the first two PAD bytes
  # (FW.22 layout — full uint16 firmware identifier, big-endian). The
  # remaining two PAD bytes are zero-filled and reserved for the
  # SEC.10 panic_counter slot.
  #
  # Distinct from build_chunk to avoid keyword/positional ambiguity at
  # call-sites that already exercise the positional API heavily.
  def build_chunk_with_params(did_hex:, rssi: 65, voltage: 4200, temp: 22,
                              acoustic: 5, metabolism: 120, status_byte: 0,
                              ttl: 5, firmware_id: 0)
    did_int   = did_hex.to_i(16)
    did_bytes = [ did_int ].pack("N")
    rssi_byte = [ rssi ].pack("C")
    pad       = [ firmware_id ].pack("n") + "\x00\x00"
    payload   = [ did_int, voltage, temp, acoustic, metabolism, status_byte, ttl ]
                  .pack("N n c C n C C") + pad
    did_bytes + rssi_byte + payload
  end

  # 21-byte chunk with SEC.10 panic flag (bit 7 of status_byte) set
  # and `panic_counter` packed into PAD bytes 2..3 (uint16 BE).
  # Acoustic=255 mirrors the chainsaw-detection signature firmware
  # asserts before emergency TX.
  def build_panic_chunk(did_hex, panic_counter, firmware_id: 0,
                        rssi: -70, voltage: 3500, temp: 25, metabolism: 100, ttl: 5)
    pad = [ firmware_id, panic_counter ].pack("n n")  # 4 bytes: fw_id BE + counter BE
    build_chunk(did_hex, rssi, voltage, temp, 0xFF, metabolism,
                TelemetryUnpackerService::PANIC_FLAG_BIT, ttl, pad)
  end

  # ---------------------------------------------------------------------
  # 25-byte AES-128-CCM chunk (FW.2 / ARCH.42 Variant B wire format).
  #
  #   [DID:4][RSSI:1][FrameCounter:4 BE][ciphertext:8][MIC:8]
  #
  # Plaintext sensor layout (8 bytes, `CCM_SENSOR_PAYLOAD_FORMAT`):
  #   vcap_mv(2), temp_c(1), acoustic(1), delta_t_s(2),
  #   status_byte(1), mesh_ctrl(1)
  #
  # `mesh_ctrl` packs `[ttl:4 high | fw_nibble:4 low]`.
  #
  # `did_hex:` and `key:` are required — no implicit lookup from
  # surrounding `let` bindings. Specs that share a fixed key/DID
  # across many calls should define a thin local wrapper that fills
  # them in, keeping this helper pure and reusable.
  # ---------------------------------------------------------------------
  def build_ccm_chunk(did_hex:, key:, rssi:, vcap:, temp:, acoustic:, dt:, status:, ttl:,
                      fw_nibble: 0, fc: 1)
    did_int   = did_hex.to_i(16)
    did_bytes = [ did_int ].pack("N")
    mesh_ctrl = ((ttl & 0x0F) << 4) | (fw_nibble & 0x0F)
    plaintext = [ vcap, temp, acoustic, dt, status, mesh_ctrl ].pack("n c C n C C")
    ct, mic   = Cryptography::LoraCcm.encrypt(
      key: key, did_bytes: did_bytes, frame_counter: fc, plaintext: plaintext
    )
    did_bytes + [ -rssi ].pack("C") + [ fc ].pack("N") + ct + mic
  end
end

RSpec.configure do |config|
  # Auto-include for any spec whose path contains "telemetry" under
  # services / integration / workers. Narrow scope keeps the global
  # spec namespace clean and avoids accidental collisions.
  config.include TelemetryChunkHelper,
                 file_path: %r{spec/(?:services|integration|workers)/.*telemetry}i
end
