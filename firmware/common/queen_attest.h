// =========================================================================
// queen_attest.h — [L1 QATT] Trust-origin L1: Queen-attestation батч-конверт
// =========================================================================
// One-Home розкладка ПІДПИСАНОГО CoAP-батча (Queen → Rails) — рунг L1
// драбини довіри (канон драбини: docs/05_02 «Trust-origin ladder»;
// wire-дім: docs/03_05 §2.2). Чиста layout-математика без HAL —
// компілюється і у прошивку Королеви, і в host-тести (вбиває
// mirror-drift, той самий патерн, що logmel/lora_ccm).
//
// Підписаний payload (v1):
//   [ver:1=0x01][queen_unix_ts:4 BE][flush_seq:4 BE][IV:16][ct:N×16][sig:64]
//   довжина % 16 == 9 — детерміністичне розрізнення від legacy
//   [IV:16][ct:N×16] (довжина % 16 == 0), без magic-вгадування проти
//   випадкового IV.
//
// Повідомлення підпису (PureEdDSA, RFC 8032 — сумісне з ruby `ed25519`):
//   "SLKN-QATT1" ‖ uid_len:1 ‖ uid ‖ <переданий payload БЕЗ хвостового sig>
// Доменний тег — проти cross-protocol reuse; UID (той самий, що в CoAP
// URI-Path) вшитий у повідомлення — батч однієї Королеви не сплайснути
// в URI іншої; uid_len робить конкатенацію однозначною. Encrypt-then-sign:
// бекенд верифікує ДО decrypt (жодних padding-оракулів).
//
// Геометрія спільного буфера (звідки беруться зсуви):
//   [prefix-зона ≤ QATT_HDR_OFFSET][header 9][IV 16][ct ≤ QATT_CT_MAX][sig 64]
// Префікс домену+UID (НЕ передається) право-вирівнюється впритул до
// header'а → повідомлення підпису = один безперервний зріз без другого
// кілобайтного RAM-буфера. ct лежить на 16-вирівняному зсуві — HAL_CRYP
// жує uint32-слова.

#ifndef QUEEN_ATTEST_H
#define QUEEN_ATTEST_H

#include <stdint.h>
#include <string.h>

#define QATT_VERSION_1       0x01u
#define QATT_HEADER_LEN      9u    /* [ver:1][unix_ts:4][flush_seq:4] */
#define QATT_IV_LEN          16u
#define QATT_SIG_LEN         64u   /* Ed25519 detached signature */

/* Хвостовий residue підписаного payload: (9 + 16 + 64) % 16 == 9.
   Legacy [IV][ct] завжди ≡ 0 (mod 16) — розрізнення детерміністичне. */
#define QATT_RESIDUE         ((QATT_HEADER_LEN + QATT_IV_LEN + QATT_SIG_LEN) % 16u)

#define QATT_DOMAIN_TAG      "SLKN-QATT1"
#define QATT_DOMAIN_TAG_LEN  10u   /* без NUL */
#define QATT_UID_MAX         31u   /* дзеркало QUEEN_UID_MAX_LEN-1 (NUL лишається в main.c) */
#define QATT_PREFIX_MAX      (QATT_DOMAIN_TAG_LEN + 1u + QATT_UID_MAX)

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
_Static_assert(QATT_RESIDUE == 9u, "signed-vs-legacy length residue contract");
_Static_assert((QATT_CT_OFFSET % 16u) == 0u, "ct must stay 16-aligned for HAL_CRYP");
#endif

/* Пише 9-байтний header [ver|unix_ts BE|flush_seq BE]. ts == 0 легітимний
   стан «Королева ще не бачила серверного часу» (Queen без RTC — 03_02 §5а);
   тому ts/seq — observability + майбутній high-water, НЕ основний anti-replay
   (той — nonce-дайджест підпису на бекенді). */
static inline void Qatt_Write_Header(uint8_t *hdr, uint32_t unix_ts,
                                     uint32_t flush_seq)
{
    hdr[0] = QATT_VERSION_1;
    hdr[1] = (uint8_t)(unix_ts >> 24);
    hdr[2] = (uint8_t)(unix_ts >> 16);
    hdr[3] = (uint8_t)(unix_ts >> 8);
    hdr[4] = (uint8_t)(unix_ts & 0xFFu);
    hdr[5] = (uint8_t)(flush_seq >> 24);
    hdr[6] = (uint8_t)(flush_seq >> 16);
    hdr[7] = (uint8_t)(flush_seq >> 8);
    hdr[8] = (uint8_t)(flush_seq & 0xFFu);
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
