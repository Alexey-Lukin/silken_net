// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * ota_seal_wire.h — [FW.23, ⚖️ founder 2026-10-05/06] wire-формат трейлера печатки
 * OTA-контракту. Pure, без криптографії: його включає й Королева (сліпий гонець — тримає
 * 16-байтні блоки й викидає їх в ефір як є), і Солдат (через ota_seal.h, де живе
 * перевірка). Дзеркало — `OtaPackagerService` (Ruby): зміна тут без зміни там рве OTA.
 *
 * 16-байтний LoRa-блок трейлера, маркер 0x9B:
 *   [0] 0x9B · [1..2] seg_idx BE · [3..4] total_chunks BE
 *   seg 1..6: [5..15] 11 байт Ed25519-підпису (6 × 11 = 66 ≥ 64; seg 6 — 9 байт + 2 PAD)
 *   seg 7:    [5..8] version_id BE + [9..15] PAD
 * Доти (HMAC-SHA256 під кластерним K_ota) печатка мала 32 байти й 3 сегменти + версію.
 */
#ifndef SILKEN_OTA_SEAL_WIRE_H
#define SILKEN_OTA_SEAL_WIRE_H

#include <stdint.h>
#include <string.h>

#define OTA_SEAL_MARKER           0x9Bu
#define OTA_SEAL_HEADER_SIZE      5u    /* [0x9B][seg_idx:2 BE][total:2 BE] */
#define OTA_SEAL_SEG_BYTES        11u   /* байт печатки на один LoRa-блок */
#define OTA_SEAL_SIG_BYTES        64u   /* Ed25519: R ‖ S */
#define OTA_SEAL_SIG_SEGS         6u    /* seg_idx 1..6 несуть підпис */
#define OTA_SEAL_VERSION_SEG_IDX  7u    /* seg_idx 7 несе version_id (частина підписаного) */
#define OTA_SEAL_TRAILER_CHUNKS   7u    /* 6 печаток + 1 версія */
#define OTA_SEAL_ALL_RECEIVED     0x7Fu /* біти 0..5 — печатка, біт 6 — версія */

_Static_assert(OTA_SEAL_SIG_SEGS * OTA_SEAL_SEG_BYTES >= OTA_SEAL_SIG_BYTES,
               "сегменти печатки мусять вмістити весь підпис");
_Static_assert(OTA_SEAL_ALL_RECEIVED == (1u << OTA_SEAL_TRAILER_CHUNKS) - 1u,
               "маска «все прийнято» = по біту на кожен трейлер-блок");

/* Розібрати один трейлер-блок у підпис/версію. 1 — лягло на місце; 0 — не печатка
 * (інший маркер, викликач пробує далі); -1 — маркер 0x9B, але блок кривий
 * (короткий / seg_idx поза [1..7]) — мовчки відкидати, як ефірний шум. */
static inline int Ota_Seal_Parse_Chunk(const uint8_t *chunk, uint16_t chunk_size,
                                       uint8_t sig_out[OTA_SEAL_SIG_BYTES],
                                       uint32_t *version_out, uint8_t *segs_inout)
{
    if (chunk == NULL || sig_out == NULL || version_out == NULL || segs_inout == NULL) return -1;
    if (chunk_size < OTA_SEAL_HEADER_SIZE + OTA_SEAL_SEG_BYTES)                         return -1;
    if (chunk[0] != OTA_SEAL_MARKER)                                                     return 0;

    uint16_t seg = (uint16_t)(((uint16_t)chunk[1] << 8) | chunk[2]);
    if (seg < 1u || seg > OTA_SEAL_TRAILER_CHUNKS)                                       return -1;

    const uint8_t *p = &chunk[OTA_SEAL_HEADER_SIZE];
    if (seg == OTA_SEAL_VERSION_SEG_IDX) {
        *version_out = ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) |
                       ((uint32_t)p[2] << 8)  |  (uint32_t)p[3];
    } else {
        uint8_t base = (uint8_t)((seg - 1u) * OTA_SEAL_SEG_BYTES);
        uint8_t len  = (seg == OTA_SEAL_SIG_SEGS) ? (uint8_t)(OTA_SEAL_SIG_BYTES - base)  /* 64 − 55 = 9 */
                                                  : (uint8_t)OTA_SEAL_SEG_BYTES;
        memcpy(&sig_out[base], p, len);
    }
    *segs_inout |= (uint8_t)(1u << (seg - 1u));
    return 1;
}

#endif /* SILKEN_OTA_SEAL_WIRE_H */
