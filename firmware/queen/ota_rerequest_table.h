// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * ota_rerequest_table.h — [FW.68 · FW.27-B] що Королева винна кожному Солдатові, який
 * перепитав (зойк 0x55, ota_rerequest_wire.h). Pure; host-тести — test_queen_logic.c.
 *
 * Чому таблиця, а не залп у відповідь (⚖️ FW.68, 03_02 §5.1.3): після зойку Солдат
 * засинає, тож залп летить у сон; вухо Солдата бере ОДИН пакет за пробудження
 * (ADR FW.52); а єдине чуте рандеву — постріл услід за ЙОГО кадром
 * (Queen_Reflex_Shots). Тому зойк лише записується, а борг віддається по блоку
 * на кожен наступний почутий кадр цього DID. Дедуп не потрібен: записати той самий
 * запит удруге — не дія, а темп обмежують каденс зойку й лімітер ефіру (FW.61).
 *
 * Місткість — OTA_RR_SLOTS Солдатів, що перепитують одночасно; новий DID за повної
 * таблиці витісняє слот по колу. Витіснений Солдат перепитає наступним зойком.
 */
#ifndef SILKEN_OTA_REREQUEST_TABLE_H
#define SILKEN_OTA_REREQUEST_TABLE_H

#include <stdint.h>
#include <string.h>
#include "../common/ota_rerequest_wire.h"
#include "ota_sha_guard.h"

#define OTA_RR_SLOTS 8u

typedef struct {
    uint32_t did;
    uint16_t total;                              /* total тіла або OTA_REQ_SEAL_SENTINEL */
    uint8_t  missing[OTA_REQ_BITMAP_MAX_BYTES];  /* біт = блок, який ще винні */
    uint8_t  used;
} OtaRrSlot;

typedef struct {
    OtaRrSlot slot[OTA_RR_SLOTS];
    uint8_t   evict_next;
} OtaRrTable;

static inline void Ota_Rr_Clear(OtaRrTable *t) { memset(t, 0, sizeof *t); }

/* Чи зойк узагалі можна обслужити. Тіло — лише з того самого буфера (вікно живе або
 * SHA-256 збігся, FW.52) і з тим самим total; печатка — лише коли Королева тримає
 * трейлер цілком. */
static inline uint8_t Ota_Rr_Admissible(const uint8_t req[OTA_REQ_PACKET_SIZE],
                                        uint16_t body_total, uint8_t body_buffer_same,
                                        uint8_t seal_held)
{
    if (req[0] != OTA_REQ_MARKER) return 0;
    uint16_t total = Ota_Req_Total(req);
    if (total == OTA_REQ_SEAL_SENTINEL) return seal_held;
    return (uint8_t)(body_total != 0u && body_buffer_same && total == body_total);
}

/* Чи буфер тіла досі той, з якого Солдат збирав: вікно живе (буфер свіжий за
 * побудовою) або SHA-256 поточного вмісту = персистованому при прийомі (FW.52). */
static inline uint8_t Ota_Rr_Body_Buffer_Same(const FlashKvOps *ops, void *io,
                                              const uint8_t *bytecode, uint16_t size,
                                              uint8_t window_active)
{
    return (uint8_t)(size > 0u &&
                     (window_active || Ota_Sha_Verify(ops, io, bytecode, size)));
}

static inline int Ota_Rr_Find(const OtaRrTable *t, uint32_t did)
{
    for (uint8_t i = 0; i < OTA_RR_SLOTS; i++) {
        if (t->slot[i].used && t->slot[i].did == did) return i;
    }
    return -1;
}

/* Записати (чи замінити) борг перед DID. Біти поза ємністю зрізаються: тіло — перші
 * min(total, 72), печатка — лише блоки seg 1..7. Порожній запит знімає наявний борг.
 * 1 — записано, 0 — нічого не винні. */
static inline uint8_t Ota_Rr_Record(OtaRrTable *t, const uint8_t req[OTA_REQ_PACKET_SIZE])
{
    uint32_t did   = Ota_Req_Did(req);
    uint16_t total = Ota_Req_Total(req);
    uint8_t  missing[OTA_REQ_BITMAP_MAX_BYTES];
    memcpy(missing, &req[OTA_REQ_HEADER_SIZE], OTA_REQ_BITMAP_MAX_BYTES);

    uint16_t cap = (total == OTA_REQ_SEAL_SENTINEL) ? (uint16_t)OTA_SEAL_TRAILER_CHUNKS
                 : (total > OTA_REQ_BODY_CAP)       ? (uint16_t)OTA_REQ_BODY_CAP
                                                    : total;
    uint8_t any = 0;
    for (uint16_t i = 0; i < OTA_REQ_BODY_CAP; i++) {
        uint8_t bit = (uint8_t)(1u << (i % 8u));
        if (i >= cap) missing[i / 8u] &= (uint8_t)~bit;
        else if (missing[i / 8u] & bit) any = 1;
    }

    int s = Ota_Rr_Find(t, did);
    if (!any) {
        if (s >= 0) t->slot[s].used = 0;
        return 0;
    }
    if (s < 0) {
        for (uint8_t i = 0; i < OTA_RR_SLOTS && s < 0; i++) {
            if (!t->slot[i].used) s = i;
        }
    }
    if (s < 0) {
        s = t->evict_next;
        t->evict_next = (uint8_t)((t->evict_next + 1u) % OTA_RR_SLOTS);
    }
    t->slot[s].did   = did;
    t->slot[s].total = total;
    memcpy(t->slot[s].missing, missing, OTA_REQ_BITMAP_MAX_BYTES);
    t->slot[s].used  = 1;
    return 1;
}

/* Перший блок, який винні почутому DID (без зміни стану — лімітер ефіру вирішує,
 * чи постріл відбудеться). Повертає слот або -1; *is_seal — трейлер, *index —
 * номер чанка тіла чи 0-базний номер трейлер-блоку (seg = index + 1). */
static inline int Ota_Rr_Peek(const OtaRrTable *t, uint32_t did,
                              uint8_t *is_seal, uint16_t *index)
{
    int s = Ota_Rr_Find(t, did);
    if (s < 0) return -1;
    for (uint16_t i = 0; i < OTA_REQ_BODY_CAP; i++) {
        if (t->slot[s].missing[i / 8u] & (uint8_t)(1u << (i % 8u))) {
            *is_seal = (uint8_t)(t->slot[s].total == OTA_REQ_SEAL_SENTINEL);
            *index   = i;
            return s;
        }
    }
    return -1;
}

/* Блок відстріляно — борг зменшився; порожній слот звільняється. */
static inline void Ota_Rr_Mark_Sent(OtaRrTable *t, int s, uint16_t index)
{
    if (s < 0 || (uint8_t)s >= OTA_RR_SLOTS || index >= OTA_REQ_BODY_CAP) return;
    t->slot[s].missing[index / 8u] &= (uint8_t)~(1u << (index % 8u));
    for (uint8_t b = 0; b < OTA_REQ_BITMAP_MAX_BYTES; b++) {
        if (t->slot[s].missing[b]) return;
    }
    t->slot[s].used = 0;
}

static inline void Ota_Rr_Drop(OtaRrTable *t, int s)
{
    if (s >= 0 && (uint8_t)s < OTA_RR_SLOTS) t->slot[s].used = 0;
}

#endif /* SILKEN_OTA_REREQUEST_TABLE_H */
