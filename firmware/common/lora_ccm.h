// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * lora_ccm.h — Shared AES-128-CCM packet helpers for Soldier ↔ Queen.
 *
 * [FW.2 / ARCH.42 Variant B, freeze-contract 2026-05-24;
 *  wire-rev2 28B — founder decision 2026-06-12, docs/03_05 wire-budget ledger]
 *
 * Single source of truth for the CCM LoRa packet format (air =
 * FW2_CCM_AIR_PACKET_LEN — 30 B since rev2.1),
 * Frame Counter packing into RTC_BKP_DR15, and CCM HAL invocation
 * shape. Used by:
 *   - firmware/soldier/main.c  (encrypt path, gated #if FW2_CCM_ENABLED)
 *   - firmware/queen/main.c    (off the hot path: the Queen is a blind courier;
 *                               Queen_Parse_CCM_LoRa_Packet serves bench RX attestation)
 *   - firmware/test/test_ccm.c (host tests, libcrypto-backed HAL mock)
 *
 * Wire format (30 bytes on the air — rev2.1, founder decision 2026-07-03
 * [E.63 гейт (г)]; Queen prepends RSSI byte before forwarding the 31-byte
 * chunk over CoAP to Rails). Airtime note [FW.61, corrected 2026-09-11]:
 * at the SHIPPING profile — SF9/125kHz/CR4:5, `common/lora_phy.h` — the
 * 27..30B frames share ONE symbol block (43 symbols, 226.3 ms), so the
 * +2B EMA field rides airtime-free inside the block rev2 already paid
 * for (wire-budget ledger, docs/03_05 §2.1): the frame homes EVERY known
 * claimant (device_z, diag bits, VPD, gossip, EMA-delta_t) so no field
 * migration was pending at rev2.1. ⊕ wire-rev2.2 (⚖️ founder 2026-10-08,
 * ledger docs/03_05 §2.1, implemented 00_07 FW.66) re-homes bytes 11 ·
 * 16..17 · 18 · 19 under branch (Б) in the same 30 B — the map below is
 * rev2.2, the bytes this firmware packs. The length is unchanged, so the
 * frame carries no revision discriminator: safe only because no CCM frame
 * has flown in the field before the FW.2 flip (ledger «Ціна»).
 * ⚠️ This line said SF10 / "28..31B / 48 symbols / 493.6 ms" until the
 * profile was reconciled: those are LoRaWAN-detour numbers (ARCH.34), not
 * ours. The conclusion survived the correction — 28B and 30B are still one
 * block — but 30B is now the LAST byte of it, so a 31st byte costs +20.5 ms
 * rather than nothing. Do not restate block edges here: read them from the
 * table in 03_05 §2.1, which `tools/firmware/lora_airtime.rb` recomputes.
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
 *   │ Byte 11   : SEC.20 contract report [reverted:1 | id7]        │
 *   │             (Fw_Report_To_Ccm7, fw_report.h) — і в panic-   │
 *   │             кадрі: доти тут їхав акустичний лічильник (з     │
 *   │             HW.30 завжди 0), код часу 0xFE і panic-код 0xFF  │
 *   │ Byte 12..13: delta_t_s (uint16 BE, seconds — RAW останнього  │
 *   │             циклу; діагностика + server-side EMA, 03_01 §13.6)│
 *   │ Byte 14   : status_byte [panic:1 | status:2 | growth:5]      │
 *   │ Byte 15   : mesh_ctrl  [ttl:4 | fw_epoch_nibble:4]           │
 *   │ Byte 16..17: voc_mv (uint16 BE, мВ V_OC EBFC, HW.19); 0 =     │
 *   │             «не виміряно» — лише спроба max-hold, що         │
 *   │             завершилась після попереднього кадру             │
 *   │ Byte 18   : diag [reset_cause:3 | time_uncertain:1 |         │
 *   │             voc_attempt:1 | резерв:2 | fc_degraded:1]        │
 *   │ Byte 19   : vpd_index (uint8, HW.32); 0 = «немає сенсора»    │
 *   │ Byte 20..21: ema_delta_t_s (uint16 BE, seconds — [E.63 (г)]  │
 *   │             КОНТРАКТ «wire = вхід GP»: це САМЕ число пішло у │
 *   │             mruby metabolic_health цього циклу (сатуроване   │
 *   │             min(EMA,0xFFFF); не-warmed → DELTA_T_UNKNOWN_S   │
 *   │             = 0, НЕ 60 [ARCH.102]; panic теж → 0). Сентинел  │
 *   │             тут несучий: 60 мапиться у GP = максимум, тобто  │
 *   │             «нейтральний» baseline був би екстремумом виходу │
 *   │             грошового шляху. Stateless GP-recompute: backend │
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
 *     2. Payload-фаза: HAL_CRYP_Encrypt/Decrypt (Size у БАЙТАХ — FW2_CCM_PLAINTEXT_LEN).
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
 * а wire ревізується лише пакетом ревізії (budget-ledger 03_05 §2.1). */
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

/* «Не виміряно» полів wire-rev2.2 — у самому значенні, без окремих біт валідності
 * (ledger 03_05 §2.1, найслабша ланка (1)). Дзеркала: VOC_MV_UNKNOWN (voc_maxhold.h) і
 * BME280_VPD_INDEX_MIN − 1 (bme280.h); рівність пінять test_voc_maxhold.c і test_bme280.c,
 * бекенд читає ті самі нулі (TelemetryUnpackerService). */
#define FW2_VOC_MV_UNKNOWN         0u
#define FW2_VPD_INDEX_NONE         0u

/* diag byte (byte 18), wire-rev2.2 = [reset_cause:3 | time_uncertain:1 |
 * voc_attempt:1 | резерв:2 | fc_degraded:1].
 * reset_cause — код firmware/common/reset_cause.h (0 = «не повідомлено», FW.59);
 * time_uncertain — Солдат ще не чув часу (soldier_unix_ts == 0, ARCH.41-B; у
 * rev2.1 цей сигнал їхав кодом 0xFE у байті 11); voc_attempt — спроба max-hold
 * V_OC завершилась (voc_mv 0 з voc_attempt 1 = «міряв, вікно зіпсоване», з 0 —
 * «не міряв»); fc_degraded — FW.2 I-HW сторожа, біт не рухався з rev2 (у rev2.1
 * над ним жили thr_invalid і fauna-біти — з HW.30 без писача). Дзеркало бітів у
 * бекенді — TelemetryUnpackerService::CCM_DIAG_*, рівність пінить спека. */
#define FW2_DIAG_RESET_CAUSE_SHIFT  5u
#define FW2_DIAG_RESET_CAUSE_MASK   0x07u
#define FW2_DIAG_TIME_UNCERTAIN_BIT 0x10u
#define FW2_DIAG_VOC_ATTEMPT_BIT    0x08u
#define FW2_DIAG_RESERVED_MASK      0x06u
#define FW2_DIAG_FC_DEGRADED_BIT    0x01u

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
 * [flags:1][nonce:12][Q:3 BE] — Q = довжина plaintext'а (FW2_CCM_PLAINTEXT_LEN).
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

/* Код поза 0..7 не обрізається маскою в ЧУЖИЙ код — він стає «не повідомлено». */
static inline uint8_t Pack_FW2_Diag(uint8_t reset_cause, uint8_t time_uncertain,
                                    uint8_t voc_attempt, uint8_t fc_degraded) {
    uint8_t cause = (reset_cause <= FW2_DIAG_RESET_CAUSE_MASK) ? reset_cause : 0u;
    return (uint8_t)((uint8_t)(cause << FW2_DIAG_RESET_CAUSE_SHIFT) |
                     (time_uncertain ? FW2_DIAG_TIME_UNCERTAIN_BIT : 0u) |
                     (voc_attempt    ? FW2_DIAG_VOC_ATTEMPT_BIT    : 0u) |
                     (fc_degraded    ? FW2_DIAG_FC_DEGRADED_BIT    : 0u));
}

static inline void Pack_CCM_Sensor_Payload(uint16_t vcap_mv, int8_t temp_c,
                                           uint8_t fw_report7, uint16_t delta_t_s,
                                           uint8_t status_byte, uint8_t mesh_ctrl,
                                           uint16_t voc_mv, uint8_t diag,
                                           uint8_t vpd_index, uint16_t ema_delta_t_s,
                                           uint8_t out[FW2_CCM_PLAINTEXT_LEN]) {
    out[0]  = (uint8_t)(vcap_mv >> 8);
    out[1]  = (uint8_t)(vcap_mv);
    out[2]  = (uint8_t)temp_c;
    out[3]  = fw_report7;
    out[4]  = (uint8_t)(delta_t_s >> 8);
    out[5]  = (uint8_t)(delta_t_s);
    out[6]  = status_byte;
    out[7]  = mesh_ctrl;
    out[8]  = (uint8_t)(voc_mv >> 8);
    out[9]  = (uint8_t)(voc_mv);
    out[10] = diag;
    out[11] = vpd_index;
    out[12] = (uint8_t)(ema_delta_t_s >> 8);
    out[13] = (uint8_t)(ema_delta_t_s);
}

/* Plaintext panic-кадру wire-rev2.2 — ОДИН дім panic-літералів (скіл firmware #25:
 * у байта більше одного писача). Сенсорних полів паніка не несе (нулі, як legacy),
 * EMA = 0 (не-гомеостаз — бекенд recompute пропускає), voc/vpd — свої «не виміряно»;
 * а байт 11 несе той самий SEC.20-звіт, що й телеметрія: доти тут стояв panic-код
 * 0xFF, і в rev2.2 він читався б відкатом із critical-алертом `firmware_reverted`.
 * Паніку бекенд читає з біта статусу, не з коду. */
static inline void Pack_CCM_Panic_Payload(uint8_t fw_report7, uint8_t mesh_ctrl,
                                          uint8_t diag,
                                          uint8_t out[FW2_CCM_PLAINTEXT_LEN]) {
    Pack_CCM_Sensor_Payload(0u, 0, fw_report7, 0u, (uint8_t)FW2_STATUS_PANIC_BIT,
                            mesh_ctrl, (uint16_t)FW2_VOC_MV_UNKNOWN, diag,
                            (uint8_t)FW2_VPD_INDEX_NONE, 0u, out);
}

static inline void Unpack_CCM_Sensor_Payload(const uint8_t in[FW2_CCM_PLAINTEXT_LEN],
                                             uint16_t *vcap_mv, int8_t *temp_c,
                                             uint8_t *fw_report7, uint16_t *delta_t_s,
                                             uint8_t *status_byte, uint8_t *mesh_ctrl,
                                             uint16_t *voc_mv, uint8_t *diag,
                                             uint8_t *vpd_index, uint16_t *ema_delta_t_s) {
    *vcap_mv       = (uint16_t)((in[0] << 8) | in[1]);
    *temp_c        = (int8_t)in[2];
    *fw_report7    = in[3];
    *delta_t_s     = (uint16_t)((in[4] << 8) | in[5]);
    *status_byte   = in[6];
    *mesh_ctrl     = in[7];
    *voc_mv        = (uint16_t)((in[8] << 8) | in[9]);
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

/* [SEC.41] Наступний FC — НАСИЧЕННЯ, не перехід через нуль: 24-бітний простір
 * одноразовий на ключ, і на вичерпанні TX відмовляє, доки re-provision у
 * нову епоху (свіжий журнал із 0x14, docs/03_05 §3.8; ратчет FW.17 якоря не
 * скидає) не відкриє нову епоху nonce. Перехід через нуль доти повторював
 * nonce: якір 0x14 застигав на 0xFFFFFF, і кожен cold start знову видавав
 * FC = 1, 2, … під тим самим KEYL. 1 → *next_out валідний; 0 → простір вичерпано,
 * *next_out не чіпаємо. */
static inline int Fw2_Next_Frame_Counter(uint32_t fc, uint32_t *next_out) {
    if (fc >= FW2_FC_VALUE_MASK) return 0;
    *next_out = fc + 1u;
    return 1;
}

#endif /* LORA_CCM_H */
