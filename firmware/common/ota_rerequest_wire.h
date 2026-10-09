// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * ota_rerequest_wire.h — [FW.27-B · FW.68] зойк Солдата «повтори, Королево» (uplink 0x55).
 * Pure: його збирає Солдат і розбирає Королева, тож обидва включають цей файл, а
 * host-тести кличуть ті самі функції, а не їхні копії (гоча firmware #19).
 *
 * Один 16-байтний ECB-блок під KEYB (control-plane, 03_05 §6):
 *   [0]     0x55
 *   [1..4]  DID (BE)
 *   [5..6]  total (BE):
 *             кількість LoRa-чанків тіла → [7..15] бітмап тіла: біт i = чанк i БРАКУЄ
 *             (LSB-first, i < 72 — більше в 9 байтів не влазить);
 *             OTA_REQ_SEAL_SENTINEL (0xFFFF) → тіло зібране, бракує печатки:
 *             [7] біти 0..6 = трейлер-блоки seg 1..7, яких БРАКУЄ; [8..15] — нулі.
 *
 * Відповідь Королеви — НЕ залп одразу (Солдат після зойку засинає), а адресний
 * рефлекс-постріл на наступний почутий кадр цього DID, по блоку за раз
 * (ota_rerequest_table.h; ⚖️ FW.68, 03_02 §5.1.3).
 */
#ifndef SILKEN_OTA_REREQUEST_WIRE_H
#define SILKEN_OTA_REREQUEST_WIRE_H

#include <stdint.h>
#include <string.h>
#include "ota_seal_wire.h"

#define OTA_REQ_MARKER            0x55u
#define OTA_REQ_HEADER_SIZE       7u
#define OTA_REQ_BITMAP_MAX_BYTES  9u
#define OTA_REQ_PACKET_SIZE       16u
#define OTA_REQ_BODY_CAP          (OTA_REQ_BITMAP_MAX_BYTES * 8u)   /* 72 чанки */
#define OTA_REQ_SEAL_SENTINEL     0xFFFFu

_Static_assert(OTA_REQ_HEADER_SIZE + OTA_REQ_BITMAP_MAX_BYTES == OTA_REQ_PACKET_SIZE,
               "зойк — рівно один AES-блок");
_Static_assert(OTA_SEAL_TRAILER_CHUNKS <= 8u,
               "маска печатки мусить влазити в один байт бітмапа");

typedef enum {
    OTA_REQ_NONE = 0,   /* нема чого перепитувати */
    OTA_REQ_BODY = 1,   /* бракує чанків тіла */
    OTA_REQ_SEAL = 2    /* тіло зібране, бракує печатки */
} OtaReqKind;

/* Чого бракує збиранню Солдата. Печатку перепитують лише за повного тіла:
 * поки тіло неповне, трейлер однаково не фіналізує нічого. */
static inline OtaReqKind Ota_Req_Kind(uint16_t total_chunks, uint16_t chunks_received,
                                      uint8_t seal_segs)
{
    if (total_chunks == 0u)                      return OTA_REQ_NONE;
    if (chunks_received < total_chunks)          return OTA_REQ_BODY;
    if (seal_segs != OTA_SEAL_ALL_RECEIVED)      return OTA_REQ_SEAL;
    return OTA_REQ_NONE;
}

/* Скільки тихих пробуджень з відкритим вухом до зойку: «5 хв тиші» лічимо
 * ПРОБУДЖЕННЯМИ, бо HAL_GetTick заморожений у STOP2 (10 × цикл 26-32 с ≈ 5 хв). */
#define OTA_REREQUEST_SILENT_WAKEUPS  10u

/* Епілог вуха Фази 4.5: якщо є що перепитувати і Королеву вже чули, ця тиха ніч
 * іде в лічильник; 1 — час зойкнути. Лічильник у нуль скидає ВИКЛИКАЧ, коли зойк
 * справді відлетів, а новий блок (тіла чи печатки) — у гілці прийому. */
static inline uint8_t Ota_Req_Silence_Due(OtaReqKind kind, uint8_t heard_before,
                                          uint8_t *silent_wakeups)
{
    if (kind == OTA_REQ_NONE || !heard_before || silent_wakeups == NULL) return 0;
    if (*silent_wakeups < 255u) (*silent_wakeups)++;
    return (uint8_t)(*silent_wakeups >= OTA_REREQUEST_SILENT_WAKEUPS);
}

static inline void Ota_Req_Header(uint32_t did, uint16_t total, uint8_t out[OTA_REQ_PACKET_SIZE])
{
    memset(out, 0, OTA_REQ_PACKET_SIZE);
    out[0] = OTA_REQ_MARKER;
    out[1] = (uint8_t)(did >> 24);
    out[2] = (uint8_t)(did >> 16);
    out[3] = (uint8_t)(did >> 8);
    out[4] = (uint8_t)(did & 0xFFu);
    out[5] = (uint8_t)(total >> 8);
    out[6] = (uint8_t)(total & 0xFFu);
}

/* Зойк про тіло. chunks_received[] — літопис збирання (прапор на слот).
 * 1 — є хоч один пропуск серед перших 72 (кадр готовий), 0 — зойк не потрібен. */
static inline uint8_t Ota_Req_Build_Body(uint32_t did, uint16_t total_chunks,
                                         const uint8_t *chunks_received,
                                         uint16_t chunks_received_size,
                                         uint8_t out[OTA_REQ_PACKET_SIZE])
{
    if (total_chunks == 0u || total_chunks == OTA_REQ_SEAL_SENTINEL) return 0;
    if (chunks_received == NULL || out == NULL)                      return 0;

    Ota_Req_Header(did, total_chunks, out);
    uint16_t cap = (total_chunks > OTA_REQ_BODY_CAP) ? (uint16_t)OTA_REQ_BODY_CAP : total_chunks;
    uint8_t any_missing = 0;
    for (uint16_t i = 0; i < cap; i++) {
        uint8_t got = (i < chunks_received_size) ? chunks_received[i] : 0u;
        if (!got) {
            out[OTA_REQ_HEADER_SIZE + i / 8u] |= (uint8_t)(1u << (i % 8u));
            any_missing = 1;
        }
    }
    return any_missing;
}

/* Зойк про печатку: сентинел замість total, маска відсутніх трейлер-блоків у [7]. */
static inline uint8_t Ota_Req_Build_Seal(uint32_t did, uint8_t seal_segs,
                                         uint8_t out[OTA_REQ_PACKET_SIZE])
{
    if (out == NULL) return 0;
    uint8_t missing = (uint8_t)(~seal_segs & OTA_SEAL_ALL_RECEIVED);
    if (missing == 0u) return 0;
    Ota_Req_Header(did, OTA_REQ_SEAL_SENTINEL, out);
    out[OTA_REQ_HEADER_SIZE] = missing;
    return 1;
}

static inline uint32_t Ota_Req_Did(const uint8_t req[OTA_REQ_PACKET_SIZE])
{
    return ((uint32_t)req[1] << 24) | ((uint32_t)req[2] << 16) |
           ((uint32_t)req[3] << 8)  |  (uint32_t)req[4];
}

static inline uint16_t Ota_Req_Total(const uint8_t req[OTA_REQ_PACKET_SIZE])
{
    return (uint16_t)(((uint16_t)req[5] << 8) | req[6]);
}

#endif /* SILKEN_OTA_REREQUEST_WIRE_H */
