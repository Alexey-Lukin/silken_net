/*
 * lora_ccm.h — Shared AES-128-CCM packet helpers for Soldier ↔ Queen.
 *
 * [FW.2 / ARCH.42 Variant B, freeze-contract 2026-05-24]
 *
 * Single source of truth for the 24-byte CCM LoRa packet format,
 * Frame Counter packing into RTC_BKP_DR15, and CCM HAL invocation
 * shape. Used by:
 *   - firmware/soldier/main.c  (encrypt path, gated #if FW2_CCM_ENABLED)
 *   - firmware/queen/main.c    (decrypt path, gated #if FW2_CCM_ENABLED)
 *   - firmware/test/test_ccm.c (host tests, libcrypto-backed HAL mock)
 *
 * Wire format (24 bytes on the air; Queen prepends RSSI byte before
 * forwarding the 25-byte chunk over CoAP to Rails):
 *
 *   ┌─ AAD (cleartext, MIC-protected) ─────────────────────────────┐
 *   │ Byte 0..3 : DID (uint32 BE)                                  │
 *   │ Byte 4..7 : Frame Counter (uint32 BE)                        │
 *   ├─ Ciphertext (encrypted sensor payload) ──────────────────────┤
 *   │ Byte 8..9 : Vcap (uint16 BE, mV)                             │
 *   │ Byte 10   : temp_c (int8, °C)                                │
 *   │ Byte 11   : acoustic_events (uint8, saturating)              │
 *   │ Byte 12..13: delta_t_s (uint16 BE, seconds)                  │
 *   │ Byte 14   : status_byte [panic:1 | status:2 | growth:5]      │
 *   │ Byte 15   : mesh_ctrl  [ttl:4 | fw_epoch_nibble:4]           │
 *   ├─ MIC (AES-CCM tag) ──────────────────────────────────────────┤
 *   │ Byte 16..23: MIC (8 bytes = 64-bit MAC)                      │
 *   └──────────────────────────────────────────────────────────────┘
 *
 * Nonce (12 bytes) = DID(4) || FrameCounter(4 BE) || 0x00 × 4
 *
 * Frame Counter persistence (RTC_BKP_DR15):
 *   DR15 packed = [FW2_FC_MAGIC:8 | frame_counter:24]
 *   Magic = 0x46 ("F"). Invalid magic on cold boot → Flash high-water
 *   floor first (fc_hiwater.h, KV key 0x14 — unconditional uniqueness),
 *   HRNG reseed as fallback (range 0x000001..0xFFFFFE — skip 0 and
 *   0xFFFFFF boundaries). Policy canon: docs/03_05 §2.1.
 */

#ifndef LORA_CCM_H
#define LORA_CCM_H

#include <stdint.h>
#include <string.h>

#define FW2_CCM_AIR_PACKET_LEN     24
#define FW2_CCM_AAD_LEN            8   /* DID(4) + FC(4) */
#define FW2_CCM_PLAINTEXT_LEN      8   /* sensor payload */
#define FW2_CCM_MIC_LEN            8   /* tag */
#define FW2_CCM_NONCE_LEN          12  /* DID + FC + 4 zero bytes */

/* RTC_BKP_DR15 magic marker (high 8 bits). Distinct from
 * LORENZ_STATE_MAGIC (DR19) to keep slot-marker grep'able. */
#define FW2_FC_MAGIC_BYTE          0x46u    /* 'F' */
#define FW2_FC_MAGIC_SHIFT         24
#define FW2_FC_VALUE_MASK          0x00FFFFFFu  /* 24-bit counter */
#define FW2_FC_HRNG_MIN            0x000001u
#define FW2_FC_HRNG_MAX            0xFFFFFEu

/* Status byte bit layout — same as 21B ECB packet; embedded inside
 * the encrypted payload here so a flipped bit fails the MIC. */
#define FW2_STATUS_PANIC_BIT       0x80u
#define FW2_STATUS_CODE_MASK       0x60u    /* bits 6..5 */
#define FW2_STATUS_CODE_SHIFT      5
#define FW2_STATUS_GROWTH_MASK     0x1Fu    /* bits 4..0 (0..31) */

/* mesh_ctrl byte = [ttl:4 (high) | fw_epoch_nibble:4 (low)] */
#define FW2_MESH_TTL_SHIFT         4
#define FW2_MESH_TTL_MASK          0x0Fu
#define FW2_MESH_FW_NIBBLE_MASK    0x0Fu

/* ----- pure-bit helpers (no HAL dependency, host-testable directly) ----- */

static inline void Build_CCM_AAD(uint32_t did, uint32_t frame_counter,
                                 uint8_t aad[FW2_CCM_AAD_LEN]) {
    aad[0] = (uint8_t)(did >> 24);
    aad[1] = (uint8_t)(did >> 16);
    aad[2] = (uint8_t)(did >> 8);
    aad[3] = (uint8_t)(did);
    aad[4] = (uint8_t)(frame_counter >> 24);
    aad[5] = (uint8_t)(frame_counter >> 16);
    aad[6] = (uint8_t)(frame_counter >> 8);
    aad[7] = (uint8_t)(frame_counter);
}

static inline void Build_CCM_Nonce(uint32_t did, uint32_t frame_counter,
                                   uint8_t nonce[FW2_CCM_NONCE_LEN]) {
    Build_CCM_AAD(did, frame_counter, nonce);
    nonce[8]  = 0x00;
    nonce[9]  = 0x00;
    nonce[10] = 0x00;
    nonce[11] = 0x00;
}

static inline void Pack_CCM_Sensor_Payload(uint16_t vcap_mv, int8_t temp_c,
                                           uint8_t acoustic, uint16_t delta_t_s,
                                           uint8_t status_byte, uint8_t mesh_ctrl,
                                           uint8_t out[FW2_CCM_PLAINTEXT_LEN]) {
    out[0] = (uint8_t)(vcap_mv >> 8);
    out[1] = (uint8_t)(vcap_mv);
    out[2] = (uint8_t)temp_c;
    out[3] = acoustic;
    out[4] = (uint8_t)(delta_t_s >> 8);
    out[5] = (uint8_t)(delta_t_s);
    out[6] = status_byte;
    out[7] = mesh_ctrl;
}

static inline void Unpack_CCM_Sensor_Payload(const uint8_t in[FW2_CCM_PLAINTEXT_LEN],
                                             uint16_t *vcap_mv, int8_t *temp_c,
                                             uint8_t *acoustic, uint16_t *delta_t_s,
                                             uint8_t *status_byte, uint8_t *mesh_ctrl) {
    *vcap_mv     = (uint16_t)((in[0] << 8) | in[1]);
    *temp_c      = (int8_t)in[2];
    *acoustic    = in[3];
    *delta_t_s   = (uint16_t)((in[4] << 8) | in[5]);
    *status_byte = in[6];
    *mesh_ctrl   = in[7];
}

/* ----- RTC_BKP_DR15 Frame Counter packing -----
 *
 * Cold-boot resilience: if the persisted DR15 magic byte does not
 * match FW2_FC_MAGIC_BYTE, caller restarts from the Flash high-water
 * floor (fc_hiwater.h) and only falls back to HRNG reseed when no
 * anchor exists (Soldier-side `Load_Frame_Counter`). Magic byte stays
 * constant once written and survives every STOP2 cycle so long as
 * VBAT holds.
 */

static inline uint32_t Pack_FW2_Frame_Counter(uint32_t fc_24bit) {
    return ((uint32_t)FW2_FC_MAGIC_BYTE << FW2_FC_MAGIC_SHIFT) |
           (fc_24bit & FW2_FC_VALUE_MASK);
}

/* Returns the unpacked 24-bit FC, or 0 if magic byte is invalid
 * (caller treats 0 as "needs cold-boot reseed"). */
static inline uint32_t Unpack_FW2_Frame_Counter(uint32_t packed) {
    uint8_t magic = (uint8_t)((packed >> FW2_FC_MAGIC_SHIFT) & 0xFFu);
    if (magic != FW2_FC_MAGIC_BYTE) return 0;
    return packed & FW2_FC_VALUE_MASK;
}

/* Reseed helper for cold boot. `hrng_word` is a fresh HRNG sample;
 * returned value is clamped into [FW2_FC_HRNG_MIN, FW2_FC_HRNG_MAX]
 * so we never start at 0 (which is "invalid") or 0xFFFFFF (which is
 * the saturating max). 1-in-2^24 collision probability with a live
 * Redis nonce from the prior incarnation is acceptable. */
static inline uint32_t Reseed_FW2_Frame_Counter(uint32_t hrng_word) {
    uint32_t v = hrng_word & FW2_FC_VALUE_MASK;
    if (v < FW2_FC_HRNG_MIN) v = FW2_FC_HRNG_MIN;
    if (v > FW2_FC_HRNG_MAX) v = FW2_FC_HRNG_MAX;
    return v;
}

#endif /* LORA_CCM_H */
