// SPDX-License-Identifier: AGPL-3.0-or-later
// =========================================================================
// queen_attest.h — [L1 QATT] Trust-origin L1: Queen-attestation батч-конверт
// =========================================================================
// One-Home розкладка ПІДПИСАНОГО CoAP-батча (Queen → Rails) — рунг L1
// драбини довіри (канон драбини: docs/05_02 «Trust-origin ladder»;
// wire-дім: docs/03_05 §2.2). Чиста layout-математика без HAL —
// компілюється і у прошивку Королеви, і в host-тести (вбиває
// mirror-drift, той самий патерн, що logmel/lora_ccm).
//
// Підписаний payload (v2, [ARCH.54] — health-блок у header; v1 без health
// ВИЛУЧЕНО ПОВНІСТЮ: флоту в полі нема, redefine дешевший за дуал-версію):
//   [ver:1=0x02][queen_unix_ts:4 BE][flush_seq:4 BE][health:8][IV:16][ct:N×16][sig:64]
//   довжина % 16 == 1 — детерміністичне розрізнення від legacy
//   [IV:16][ct:N×16] (довжина % 16 == 0), без magic-вгадування проти
//   випадкового IV. ct = 0 легальний (empty-flush heartbeat: конверт
//   без записів — пульс за тихої години; residue-математика та сама).
//
// Health-блок (8 байт, [ARCH.54 Шар 1] — раз на flush, ПІДПИСАНИЙ разом з
// усім конвертом → masking-attack закритий, той самий L1-рунг, що батч):
//   [0..2] uptime_min u24 BE   — sw-extended лічильник хвилин (НЕ tick/60000:
//                                 tick вмирає на 49.7d — лічильник живе роками)
//   [3]    cifo_fill  u8       — cache_count на момент flush (0..50)
//   [4]    lora_rx_drops u8    — сатурований лічильник переповнень RX-рингу
//   [5]    coap_fail  u8       — сатурований лічильник провалених flush-розмов
//   [6]    csq        u8       — 3GPP 0..31 | 99=no-signal | 0xFF=не читали
//   [7]    flags      u8       — bit0: CCM-ера (FW2), bit1: ring (ARCH.35),
//                                 bit2: були 16B-легасі-дропи цей аптайм
//                                 (atomic-cutover видимість, FW.2 гейт (а)),
//                                 bit3: були DID=0 CCM-спуф-дропи;
//                                 bit4..7 rsv=0
//   ⚖️ bit4 має ЗАБРОНЬОВАНЕ призначення (YAGNI до першої реальної
//   польової втрати PUT): QATT_HFLAG_CANARY [SEC.21] — прапорець
//   canary-trip, доставлений ГАРАНТОВАНО heartbeat'ом, як кластерний
//   early-warning ПОВЕРХ best-effort uplink 0x57. Тобто це не «вільний
//   резерв»: перш ніж зайняти bit4 чимось іншим, зніми цю бронь свідомо.
//   Поля vcap_mv / temp — СВІДОМО відсутні: Королева без ADC-тракту, брехати
//   нулями не будемо (чесність до заліза; резерв → wire-ревізія при HW).
//
// Повідомлення підпису (PureEdDSA, RFC 8032 — сумісне з ruby `ed25519`):
//   "SLKN-QATT2" ‖ uid_len:1 ‖ uid ‖ <переданий payload БЕЗ хвостового sig>
// Доменний тег — проти cross-protocol reuse (bump QATT1→QATT2 разом із
// форматом — старі вектори не можуть колізувати); UID (той самий, що в CoAP
// URI-Path) вшитий у повідомлення — батч однієї Королеви не сплайснути
// в URI іншої; uid_len робить конкатенацію однозначною. Encrypt-then-sign:
// бекенд верифікує ДО decrypt (жодних padding-оракулів).
//
// Геометрія спільного буфера (звідки беруться зсуви):
//   [prefix-зона ≤ QATT_HDR_OFFSET][header 17][IV 16][ct ≤ QATT_CT_MAX][sig 64]
// Префікс домену+UID (НЕ передається) право-вирівнюється впритул до
// header'а → повідомлення підпису = один безперервний зріз без другого
// кілобайтного RAM-буфера. ct лежить на 16-вирівняному зсуві — HAL_CRYP
// жує uint32-слова.

#ifndef QUEEN_ATTEST_H
#define QUEEN_ATTEST_H

#include <stdint.h>
#include <string.h>

#define QATT_VERSION_2       0x02u
#define QATT_HEALTH_LEN      8u
#define QATT_HEADER_LEN      17u   /* [ver:1][unix_ts:4][flush_seq:4][health:8] */
#define QATT_IV_LEN          16u
#define QATT_SIG_LEN         64u   /* Ed25519 detached signature */

/* Хвостовий residue підписаного payload: (17 + 16 + 64) % 16 == 1.
   Legacy [IV][ct] завжди ≡ 0 (mod 16) — розрізнення детерміністичне. */
#define QATT_RESIDUE         ((QATT_HEADER_LEN + QATT_IV_LEN + QATT_SIG_LEN) % 16u)

#define QATT_DOMAIN_TAG      "SLKN-QATT2"
#define QATT_DOMAIN_TAG_LEN  10u   /* без NUL */
#define QATT_UID_MAX         31u   /* дзеркало QUEEN_UID_MAX_LEN-1 (NUL лишається в main.c) */
#define QATT_PREFIX_MAX      (QATT_DOMAIN_TAG_LEN + 1u + QATT_UID_MAX)

/* Health-flags (byte 7 health-блоку) */
#define QATT_HFLAG_CCM_ERA      0x01u
#define QATT_HFLAG_RING         0x02u
/* [FW.2 гейт (а)] Wire-видимість вікна atomic-cutover'а: до цих бітів
   ccm_legacy_telemetry_drops/ccm_spoof_drops жили лише в RAM (SWD-only) —
   оператор не бачив, чи лишились непрошиті Солдати. Біт, не лічильник:
   геометрія header'а (residue==1) недоторкана; точне число — SWD. */
#define QATT_HFLAG_LEGACY_DROPS 0x04u
#define QATT_HFLAG_CCM_SPOOF    0x08u

/* csq-сентинелі (byte 6) */
#define QATT_CSQ_NO_SIGNAL   99u
#define QATT_CSQ_NOT_READ    0xFFu

/* Зсуви спільного буфера. ct = 80 (16-aligned, HAL_CRYP word-доступ);
   усе лівіше — похідне. Зона префікса (0..QATT_HDR_OFFSET) мусить вміщати
   найдовший префікс. */
#define QATT_CT_OFFSET       80u
#define QATT_IV_OFFSET       (QATT_CT_OFFSET - QATT_IV_LEN)
#define QATT_HDR_OFFSET      (QATT_IV_OFFSET - QATT_HEADER_LEN)
#define QATT_CT_MAX          2048u /* дзеркало binary_batch_buffer */
#define QATT_BUFFER_SIZE     (QATT_CT_OFFSET + QATT_CT_MAX + QATT_SIG_LEN)

#if defined(__STDC_VERSION__) && __STDC_VERSION__ >= 201112L
_Static_assert(QATT_HDR_OFFSET >= QATT_PREFIX_MAX,
               "prefix area must fit the longest domain+UID prefix");
_Static_assert(QATT_RESIDUE == 1u, "signed-vs-legacy length residue contract");
_Static_assert((QATT_CT_OFFSET % 16u) == 0u, "ct must stay 16-aligned for HAL_CRYP");
#endif

/* Пише 17-байтний header [ver|unix_ts BE|flush_seq BE|health:8]. ts == 0
   легітимний стан «Королева ще не бачила серверного часу» (Queen без RTC —
   03_02 §5а); тому ts/seq — observability + майбутній high-water, НЕ основний
   anti-replay (той — nonce-дайджест підпису на бекенді). Health-байти —
   [ARCH.54 Шар 1]; сатурації робить викликач (тут — чиста розкладка). */
static inline void Qatt_Write_Header(uint8_t *hdr, uint32_t unix_ts,
                                     uint32_t flush_seq,
                                     uint32_t uptime_min, uint8_t cifo_fill,
                                     uint8_t rx_drops, uint8_t coap_fail,
                                     uint8_t csq, uint8_t flags)
{
    hdr[0]  = QATT_VERSION_2;
    hdr[1]  = (uint8_t)(unix_ts >> 24);
    hdr[2]  = (uint8_t)(unix_ts >> 16);
    hdr[3]  = (uint8_t)(unix_ts >> 8);
    hdr[4]  = (uint8_t)(unix_ts & 0xFFu);
    hdr[5]  = (uint8_t)(flush_seq >> 24);
    hdr[6]  = (uint8_t)(flush_seq >> 16);
    hdr[7]  = (uint8_t)(flush_seq >> 8);
    hdr[8]  = (uint8_t)(flush_seq & 0xFFu);
    /* uptime u24 BE: 16.7M хв ≈ 31.9 років — стеля чесна для 25-річного
       горизонту; сатурація на викликачеві не потрібна (лічильник u32,
       клемп тут). */
    uint32_t up = (uptime_min > 0x00FFFFFFu) ? 0x00FFFFFFu : uptime_min;
    hdr[9]  = (uint8_t)(up >> 16);
    hdr[10] = (uint8_t)(up >> 8);
    hdr[11] = (uint8_t)(up & 0xFFu);
    hdr[12] = cifo_fill;
    hdr[13] = rx_drops;
    hdr[14] = coap_fail;
    hdr[15] = csq;
    hdr[16] = flags;
}

/* Право-вирівняний префікс [tag][uid_len][uid], що закінчується РІВНО на
   prefix_area + prefix_area_len (тобто впритул до header'а в спільному
   буфері). Повертає довжину префікса; 0 = UID порожній/задовгий —
   викликач мусить відкотитись на legacy-формат, не підписувати сміття. */
static inline uint16_t Qatt_Compose_Prefix(uint8_t *prefix_area,
                                           uint16_t prefix_area_len,
                                           const char *uid)
{
    size_t uid_len = (uid != NULL) ? strlen(uid) : 0u;
    if (uid_len == 0u || uid_len > QATT_UID_MAX) return 0u;

    uint16_t prefix_len = (uint16_t)(QATT_DOMAIN_TAG_LEN + 1u + uid_len);
    if (prefix_len > prefix_area_len) return 0u;

    uint8_t *p = prefix_area + prefix_area_len - prefix_len;
    memcpy(p, QATT_DOMAIN_TAG, QATT_DOMAIN_TAG_LEN);
    p[QATT_DOMAIN_TAG_LEN] = (uint8_t)uid_len;
    memcpy(p + QATT_DOMAIN_TAG_LEN + 1u, uid, uid_len);
    return prefix_len;
}

#endif /* QUEEN_ATTEST_H */
