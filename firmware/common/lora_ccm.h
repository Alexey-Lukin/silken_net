// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * lora_ccm.h — Shared AES-128-CCM packet helpers for Soldier ↔ Queen.
 *
 * [FW.2 / ARCH.42 Variant B, freeze-contract 2026-05-24;
 *  wire-rev2 28B — founder decision 2026-06-12, docs/03_05 wire-budget ledger]
 *
 * Single source of truth for the 28-byte CCM LoRa packet format,
 * Frame Counter packing into RTC_BKP_DR15, and CCM HAL invocation
 * shape. Used by:
 *   - firmware/soldier/main.c  (encrypt path, gated #if FW2_CCM_ENABLED)
 *   - firmware/queen/main.c    (decrypt path, gated #if FW2_CCM_ENABLED)
 *   - firmware/test/test_ccm.c (host tests, libcrypto-backed HAL mock)
 *
 * Wire format (30 bytes on the air — rev2.1, founder decision 2026-07-03
 * [E.63 гейт (г)]; Queen prepends RSSI byte before forwarding the 31-byte
 * chunk over CoAP to Rails). Airtime note: at SF10/125kHz/CR4:5 the
 * 28..31B frames share ONE symbol block (48 symbols, 493.6 ms) — the
 * +2B EMA field rides airtime-free inside the block rev2 already paid
 * for (wire-budget ledger, docs/03_05): the frame homes EVERY known
 * claimant (device_z, diag bits, VPD, gossip, EMA-delta_t) so no field
 * migration is pending.
 *
 *   ┌─ AAD (cleartext, MIC-protected) ─────────────────────────────┐
 *   │ Byte 0..3 : DID (uint32 BE)                                  │
 *   │ Byte 4    : gossip_ts_lsb (= unix_ts & 0xFF; 0 = час         │
 *   │             невідомий). Cleartext НАВМИСНО: сусіди-Солдати   │
 *   │             читають його без per-Soldier ключа (FW.20-S2 #5  │
 *   │             gossip переживає CCM); бекенд верифікує MIC'ом.  │
 *   │ Byte 5..7 : Frame Counter (24-bit BE — справжня ширина FC;   │
 *   │             старший байт старого FC32-поля був завжди 0x00)  │
 *   ├─ Ciphertext (encrypted sensor payload) ──────────────────────┤
 *   │ Byte 8..9 : Vcap (uint16 BE, mV)                             │
 *   │ Byte 10   : temp_c (int8, °C)                                │
 *   │ Byte 11   : acoustic_events (uint8, saturating)              │
 *   │ Byte 12..13: delta_t_s (uint16 BE, seconds — RAW останнього  │
 *   │             циклу; діагностика + server-side EMA, 03_01 §13.6)│
 *   │ Byte 14   : status_byte [panic:1 | status:2 | growth:5]      │
 *   │ Byte 15   : mesh_ctrl  [ttl:4 | fw_epoch_nibble:4]           │
 *   │ Byte 16..17: device_z (uint16 BE, z × 512; 0xFFFF = «не      │
 *   │             обчислено» — FW.31 numeric DCI, q=2⁻⁹ ⇒          │
 *   │             похибка ≤ 0.00098 < ε 0.001, діапазон 0..127.99) │
 *   │ Byte 18   : diag [thr_invalid:5 | fauna_mode:1 |             │
 *   │             fauna_skip:1 | fc_degraded:1] (FW.18b/FW.42/FW.2)│
 *   │ Byte 19   : vpd_index (uint8; 0x00 = немає BME280 — резерв   │
 *   │             під HW.32, шкала визначається при калібруванні)  │
 *   │ Byte 20..21: ema_delta_t_s (uint16 BE, seconds — [E.63 (г)]  │
 *   │             КОНТРАКТ «wire = вхід GP»: це САМЕ число пішло у │
 *   │             mruby metabolic_health цього циклу (сатуроване   │
 *   │             min(EMA,0xFFFF); не-warmed → BASELINE 60; panic  │
 *   │             → 0). Stateless GP-recompute: backend рахує      │
 *   │             m(ema) з нього ж — observational до bench-       │
 *   │             калібрування порогів. Transient (не персистить). │
 *   ├─ MIC (AES-CCM tag) ──────────────────────────────────────────┤
 *   │ Byte 22..29: MIC (8 bytes = 64-bit MAC)                      │
 *   └──────────────────────────────────────────────────────────────┘
 *
 * Nonce (12 bytes) = DID(4) || FrameCounter(4 BE, top byte 0) || 0x00 × 4
 *   — БАЙТ-У-БАЙТ як у rev1: gossip-байт у нонс НЕ входить (унікальність
 *   гарантує сам FC), тож nonce-математика і Redis replay-guard незмінні.
 *
 * CCM HAL invocation shape — WL-ІСТИНА (знахідка 2026-07-03):
 *   У STM32WLxx HAL НЕМАЄ HAL_CRYPEx_AESCCM_Encrypt/Decrypt (то API
 *   старших родин F4/F7/L4) — є лише двофазний флоу:
 *     1. Init: Algorithm=CRYP_AES_CCM + Init.B0 (форматований B0-блок,
 *        Build_CCM_B0 нижче) + Init.Header/HeaderSize (AAD) +
 *        DataWidthUnit/HeaderWidthUnit = BYTE + DataType = 8B
 *        (байтопотік без word-swap двозначностей; silicon-звірку
 *        DataType-комбінації робить ccm_selftest KAT на bench).
 *     2. Payload-фаза: HAL_CRYP_Encrypt/Decrypt (Size у БАЙТАХ — 12).
 *     3. Тег-фаза: HAL_CRYPEx_AESCCM_GenerateAuthTAG → перші 8 байт = MIC.
 *   На decrypt HAL тег НЕ звіряє — порівняння робить ВИКЛИКАЧ
 *   константним часом (Fw2_Ccm_Tag_Equal). Host-мок (hal_mock.h)
 *   віддзеркалює цей самий флоу і ВАЛІДУЄ B0 проти цього білдера.
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

#define FW2_CCM_AIR_PACKET_LEN     30  /* rev2.1: +2B EMA (E.63 гейт (г), 2026-07-03) */
#define FW2_CCM_AAD_LEN            8   /* DID(4) + gossip(1) + FC24(3) */
#define FW2_CCM_PLAINTEXT_LEN      14  /* sensor payload (wire-rev2.1) */
#define FW2_CCM_MIC_LEN            8   /* tag */
#define FW2_CCM_NONCE_LEN          12  /* DID + FC32 + 4 zero bytes */
#define FW2_CCM_B0_LEN             16  /* NIST 800-38C B0: flags‖nonce‖Q */

/* B0 flags (NIST SP 800-38C §A.2.1): Adata=1 (маємо AAD), M'=(t-2)/2 при
 * t=8, L'=q-1 при q=15-nonce_len=3 → 0x40 | 0x18 | 0x02 = 0x5A. Байт
 * зашитий константою (не рахується в рантаймі): зміна t/q = зміна wire,
 * а wire ревізується лише пакетом rev3 (budget-ledger 03_05 §2.1). */
#define FW2_CCM_B0_FLAGS           0x5Au

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

/* device_z (bytes 16..17): фіксована точка z × 512 (q = 2⁻⁹).
 * Сентинель 0xFFFF = «Лоренц цього циклу не рахувався» (ARCH.41-C grace,
 * невалідний seed) — бекенд пропускає numeric DCI-гілку (Gate D guard).
 * Стеля 0xFFFE = z 127.996 — вище за будь-який легальний z (anomaly
 * ceiling ≤ 67 при ρ_max=50, E.64), сатурація не зустрічається у полі. */
#define FW2_DEVICE_Z_SCALE         512u
#define FW2_DEVICE_Z_NONE          0xFFFFu
#define FW2_DEVICE_Z_MAX           0xFFFEu

/* diag byte (byte 18) = [thr_invalid:5 | fauna_mode:1 | fauna_skip:1 |
 * fc_degraded:1] — лічильник зверху, прапорці знизу (патерн ttl_byte.h).
 * thr_invalid — FW.18b saturating-лічильник відкинутих OTA-порогів
 * (у 21B жив у байті 11 [thr:5|TTL:3]; CCM TTL живе у mesh_ctrl).
 * fauna_mode/skip — FW.42/ARCH.40; fc_degraded — FW.2 I-HW сторожа. */
#define FW2_DIAG_THR_INVALID_SHIFT 3u
#define FW2_DIAG_THR_INVALID_MAX   31u
#define FW2_DIAG_FAUNA_MODE_BIT    0x04u
#define FW2_DIAG_FAUNA_SKIP_BIT    0x02u
#define FW2_DIAG_FC_DEGRADED_BIT   0x01u

/* ----- pure-bit helpers (no HAL dependency, host-testable directly) ----- */

/* AAD (wire bytes 0..7): DID || gossip_ts_lsb || FC 24-bit BE.
 * Gossip-байт автентифікується MIC'ом — бекенд відкине підробку;
 * сусід-Солдат читає його без ключа як НЕдовірене уточнення (та сама
 * довіра, що у ECB-piggyback — FW.20-S2 #5). */
static inline void Build_CCM_AAD(uint32_t did, uint8_t gossip_ts_lsb,
                                 uint32_t frame_counter,
                                 uint8_t aad[FW2_CCM_AAD_LEN]) {
    aad[0] = (uint8_t)(did >> 24);
    aad[1] = (uint8_t)(did >> 16);
    aad[2] = (uint8_t)(did >> 8);
    aad[3] = (uint8_t)(did);
    aad[4] = gossip_ts_lsb;
    aad[5] = (uint8_t)(frame_counter >> 16);
    aad[6] = (uint8_t)(frame_counter >> 8);
    aad[7] = (uint8_t)(frame_counter);
}

/* Nonce — байт-у-байт rev1: DID || FC32 BE (top byte 0) || 0x00×4.
 * Gossip-байт НЕ входить: унікальність (key, nonce) тримає сам FC. */
static inline void Build_CCM_Nonce(uint32_t did, uint32_t frame_counter,
                                   uint8_t nonce[FW2_CCM_NONCE_LEN]) {
    nonce[0]  = (uint8_t)(did >> 24);
    nonce[1]  = (uint8_t)(did >> 16);
    nonce[2]  = (uint8_t)(did >> 8);
    nonce[3]  = (uint8_t)(did);
    nonce[4]  = (uint8_t)(frame_counter >> 24);
    nonce[5]  = (uint8_t)(frame_counter >> 16);
    nonce[6]  = (uint8_t)(frame_counter >> 8);
    nonce[7]  = (uint8_t)(frame_counter);
    nonce[8]  = 0x00;
    nonce[9]  = 0x00;
    nonce[10] = 0x00;
    nonce[11] = 0x00;
}

/* B0-блок із ГОТОВОГО нонса (KAT-вектори носять nonce напряму):
 * [flags:1][nonce:12][Q:3 BE] — Q = довжина plaintext'а (12).
 * Це єдине місце, де форматується B0; кремній і мок їдять той самий байт-ряд. */
static inline void Build_CCM_B0_From_Nonce(const uint8_t nonce[FW2_CCM_NONCE_LEN],
                                           uint16_t payload_len,
                                           uint8_t b0[FW2_CCM_B0_LEN]) {
    b0[0] = FW2_CCM_B0_FLAGS;
    memcpy(&b0[1], nonce, FW2_CCM_NONCE_LEN);
    b0[13] = 0x00;
    b0[14] = (uint8_t)(payload_len >> 8);
    b0[15] = (uint8_t)(payload_len);
}

/* Польовий шлях: B0 прямо з DID/FC (нонс той самий, що Build_CCM_Nonce). */
static inline void Build_CCM_B0(uint32_t did, uint32_t frame_counter,
                                uint8_t b0[FW2_CCM_B0_LEN]) {
    uint8_t nonce[FW2_CCM_NONCE_LEN];
    Build_CCM_Nonce(did, frame_counter, nonce);
    Build_CCM_B0_From_Nonce(nonce, FW2_CCM_PLAINTEXT_LEN, b0);
}

/* Константний час порівняння MIC (WL-флоу: decrypt НЕ звіряє тег сам —
 * привратник дивиться однаково довго на істину і на лжесвідчення).
 * 1 = теги рівні. */
static inline int Fw2_Ccm_Tag_Equal(const uint8_t a[FW2_CCM_MIC_LEN],
                                    const uint8_t b[FW2_CCM_MIC_LEN]) {
    uint8_t diff = 0;
    for (unsigned i = 0; i < FW2_CCM_MIC_LEN; i++) diff |= (uint8_t)(a[i] ^ b[i]);
    return diff == 0;
}

/* Квантування device_z для дроту. valid=0 (Лоренц не рахувався) →
 * сентинель NONE. Від'ємний/несинченний z (не трапляється на атракторі,
 * захист від сміття) → 0. Round-to-nearest: похибка ≤ q/2 = 0.00098. */
static inline uint16_t Pack_FW2_Device_Z(float z, uint8_t valid) {
    if (!valid) return (uint16_t)FW2_DEVICE_Z_NONE;
    if (!(z > 0.0f)) return 0u; /* NaN теж сюди — чесний нуль, не сміття */
    float scaled = z * (float)FW2_DEVICE_Z_SCALE + 0.5f;
    if (scaled >= (float)FW2_DEVICE_Z_MAX) return (uint16_t)FW2_DEVICE_Z_MAX;
    return (uint16_t)scaled;
}

static inline uint8_t Pack_FW2_Diag(uint8_t thr_invalid, uint8_t fauna_mode,
                                    uint8_t fauna_skip, uint8_t fc_degraded) {
    uint8_t capped = (thr_invalid > FW2_DIAG_THR_INVALID_MAX)
                         ? (uint8_t)FW2_DIAG_THR_INVALID_MAX
                         : thr_invalid;
    return (uint8_t)((uint8_t)(capped << FW2_DIAG_THR_INVALID_SHIFT) |
                     (fauna_mode  ? FW2_DIAG_FAUNA_MODE_BIT  : 0u) |
                     (fauna_skip  ? FW2_DIAG_FAUNA_SKIP_BIT  : 0u) |
                     (fc_degraded ? FW2_DIAG_FC_DEGRADED_BIT : 0u));
}

static inline void Pack_CCM_Sensor_Payload(uint16_t vcap_mv, int8_t temp_c,
                                           uint8_t acoustic, uint16_t delta_t_s,
                                           uint8_t status_byte, uint8_t mesh_ctrl,
                                           uint16_t device_z, uint8_t diag,
                                           uint8_t vpd_index, uint16_t ema_delta_t_s,
                                           uint8_t out[FW2_CCM_PLAINTEXT_LEN]) {
    out[0]  = (uint8_t)(vcap_mv >> 8);
    out[1]  = (uint8_t)(vcap_mv);
    out[2]  = (uint8_t)temp_c;
    out[3]  = acoustic;
    out[4]  = (uint8_t)(delta_t_s >> 8);
    out[5]  = (uint8_t)(delta_t_s);
    out[6]  = status_byte;
    out[7]  = mesh_ctrl;
    out[8]  = (uint8_t)(device_z >> 8);
    out[9]  = (uint8_t)(device_z);
    out[10] = diag;
    out[11] = vpd_index;
    out[12] = (uint8_t)(ema_delta_t_s >> 8);
    out[13] = (uint8_t)(ema_delta_t_s);
}

static inline void Unpack_CCM_Sensor_Payload(const uint8_t in[FW2_CCM_PLAINTEXT_LEN],
                                             uint16_t *vcap_mv, int8_t *temp_c,
                                             uint8_t *acoustic, uint16_t *delta_t_s,
                                             uint8_t *status_byte, uint8_t *mesh_ctrl,
                                             uint16_t *device_z, uint8_t *diag,
                                             uint8_t *vpd_index, uint16_t *ema_delta_t_s) {
    *vcap_mv       = (uint16_t)((in[0] << 8) | in[1]);
    *temp_c        = (int8_t)in[2];
    *acoustic      = in[3];
    *delta_t_s     = (uint16_t)((in[4] << 8) | in[5]);
    *status_byte   = in[6];
    *mesh_ctrl     = in[7];
    *device_z      = (uint16_t)((in[8] << 8) | in[9]);
    *diag          = in[10];
    *vpd_index     = in[11];
    *ema_delta_t_s = (uint16_t)((in[12] << 8) | in[13]);
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
