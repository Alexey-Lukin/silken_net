// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * cifo_cache.h — [FW.3 · E.8 · FW.2] ядро edge-кешу Королеви: дедуп DID,
 *                вставка у вільний слот, priority-aware витіснення (CIFO).
 *
 * Pure header (без HAL): цей самий код компілюють main.c і host-тести
 * (test_queen_logic.c). ⛔ Не повертай у тест рукописну копію цих функцій:
 * копія вже раз розійшлась із прошивкою так, що сюїта зеленіла, поки
 * прошивка не рахувала вставок, — лічильник стояв на нулі, а після першого
 * флашу `cache_count -= cleared` загортав uint8_t, і тригер «кеш повний»
 * та гілка вставки брехали разом. Тому весь облік (інкремент при вставці,
 * порядок «спіл жертви → перезапис») живе ТУТ, а не в каллера.
 *
 * Лічильник — не прикраса: він тригерить флаш (≥ CACHE_MAX_ENTRIES −
 * FLUSH_HEADROOM у main.c) і дає fill_pct у health-блоці QATT.
 */
#ifndef QUEEN_CIFO_CACHE_H
#define QUEEN_CIFO_CACHE_H

#include <stdint.h>
#include <string.h>
/* FW2_CCM_AIR_PACKET_LEN — у гейтованій гілці ширини слота нижче */
#include "../common/lora_ccm.h" // IWYU pragma: keep

#define CACHE_MAX_ENTRIES 50 /* місткість RAM-кешу (слотів) */

/* [FW.2] Формат слота: ECB-ера тримає РОЗШИФРОВАНІ 16B (Королева = ключ
 * кластера); CCM-ера — ОПАКОВИЙ air-хвіст ефіру (gossip‖FC‖ct‖MIC, довжина
 * похідна = air−4) — інверсія довіри wire-rev2: розшифрує лише Rails
 * per-DID (rx_route.h). */
#define EDGE_FMT_ECB16    0u /* payload[0..15] = розшифрований legacy-блок */
#define EDGE_FMT_CCM_AIR  1u /* payload[0..air-5] = air[4..кінець] як є (опак) */

/* Ширина payload гейтована: бойовий .bss інертного CCM-гейта її не платить
 * (ціна — budget-ledger 03_05 §2.1); fmt-байт живе завжди заради одного
 * код-шляху CIFO/flush. Host-тест, що міряє обидві ери, визначає ширину сам
 * (суперсет) ДО include. */
#ifndef EDGE_SLOT_PAYLOAD_MAX
#if FW2_CCM_ENABLED
#define EDGE_SLOT_PAYLOAD_MAX  (FW2_CCM_AIR_PACKET_LEN - 4u)
#else
#define EDGE_SLOT_PAYLOAD_MAX  16u
#endif
#endif

typedef struct {
    uint32_t uid;                            /* DID дерева */
    uint8_t  payload[EDGE_SLOT_PAYLOAD_MAX]; /* розкладку й довжину диктує fmt */
    int8_t   rssi;                           /* сила сигналу */
    int8_t   snr;                            /* [E.8] tiebreaker витіснення */
    uint8_t  is_active;                      /* 0 вільний · 1 свіжий LoRa · 2 перелитий із ring (ARCH.35) */
    uint8_t  fmt;                            /* EDGE_FMT_* */
} EdgeCache;

typedef enum { CIFO_DEDUP = 0, CIFO_INSERT = 1, CIFO_EVICT = 2 } CifoOutcome;

/* Хук між вибором жертви й її перезаписом (main.c: ARCH.35-спіл у ring). */
typedef void (*CifoSpillFn)(EdgeCache *victim);

/* fmt диктує і розкладку, і ДОВЖИНУ: у бойовому ECB-білді CCM-кадр не
 * доходить до кешу (ISR тримає size-гейт), тож стеля ширини тут не ріже. */
static inline uint8_t Cifo_Payload_Len(uint8_t fmt)
{
    return (fmt == EDGE_FMT_CCM_AIR) ? (uint8_t)EDGE_SLOT_PAYLOAD_MAX : 16u;
}

/* [FW.29-PACK] bio_status = біти [6:5] байта 10 (біт 7 — PANIC_FLAG_BIT).
 * Розкладка дійсна ЛИШЕ для ECB16: у CCM-слоті byte 10 — опаковий шифртекст
 * (diag), тож сліпий кур'єр чесно ставить 0, і CCM-запис живе в пулі
 * preferred-evict — свідома стеля, довгий лік — ARCH.35 overflow-ринг. */
static inline uint8_t Cifo_Bio_Status(const EdgeCache *s)
{
    return (s->fmt == EDGE_FMT_ECB16) ? (uint8_t)((s->payload[10] >> 5) & 0x03u) : 0u;
}

static inline int Cifo_Find(const EdgeCache c[CACHE_MAX_ENTRIES], uint32_t uid)
{
    for (int i = 0; i < CACHE_MAX_ENTRIES; i++)
        if (c[i].is_active && c[i].uid == uid) return i;
    return -1;
}

/* Жертва витіснення: некритичне (status 0) дерево з найгіршим RSSI — бо
 * дерево з найгіршим RSSI може стояти на межі пожежі; якщо критичні ВСІ —
 * абсолютно найгірший RSSI. [E.8] При рівному RSSI виграє нижчий SNR
 * (шумніший канал). Неактивні слоти не порівнюються (їхній RSSI — сміття). */
static inline int Cifo_Pick_Victim(const EdgeCache c[CACHE_MAX_ENTRIES])
{
    int best = -1, fallback = 0;
    int8_t best_rssi = 127, best_snr = 127, fb_rssi = 127, fb_snr = 127;

    for (int i = 0; i < CACHE_MAX_ENTRIES; i++) {
        if (!c[i].is_active) continue;
        if (c[i].rssi < fb_rssi || (c[i].rssi == fb_rssi && c[i].snr < fb_snr)) {
            fb_rssi = c[i].rssi;
            fb_snr  = c[i].snr;
            fallback = i;
        }
        if (Cifo_Bio_Status(&c[i]) == 0 &&
            (c[i].rssi < best_rssi || (c[i].rssi == best_rssi && c[i].snr < best_snr))) {
            best_rssi = c[i].rssi;
            best_snr  = c[i].snr;
            best = i;
        }
    }
    return (best >= 0) ? best : fallback;
}

static inline uint8_t Cifo_Count_Active(const EdgeCache c[CACHE_MAX_ENTRIES])
{
    uint8_t n = 0;
    for (int i = 0; i < CACHE_MAX_ENTRIES; i++)
        if (c[i].is_active) n++;
    return n;
}

/* Голос дерева → кеш. Дедуп оновлює і байти, і fmt (перепрошите дерево
 * міняє формат між пробудженнями) і не чіпає is_active; вставка шукає
 * вільний слот незалежно від лічильника; витіснення спершу віддає жертву
 * хуку (spill може бути NULL) і лише тоді перезаписує. Свіжий LoRa-запис —
 * is_active = 1, навіть поверх перелитого (2): інакше fail-спіл «почистив
 * би» його як уже збережений у флеші. */
static inline CifoOutcome Cifo_Upsert(EdgeCache c[CACHE_MAX_ENTRIES], uint8_t *count,
                                      uint32_t uid, const uint8_t *payload,
                                      int8_t rssi, int8_t snr, uint8_t fmt,
                                      CifoSpillFn spill)
{
    CifoOutcome out = CIFO_DEDUP;
    int i = Cifo_Find(c, uid);

    if (i < 0) {
        for (int k = 0; k < CACHE_MAX_ENTRIES; k++) {
            if (!c[k].is_active) { i = k; out = CIFO_INSERT; break; }
        }
    }
    if (i < 0) {
        i = Cifo_Pick_Victim(c);
        out = CIFO_EVICT;
        if (spill) spill(&c[i]);
    }

    c[i].uid  = uid;
    memcpy(c[i].payload, payload, Cifo_Payload_Len(fmt));
    c[i].rssi = rssi;
    c[i].snr  = snr;
    c[i].fmt  = fmt;
    if (out != CIFO_DEDUP) c[i].is_active = 1;
    if (out == CIFO_INSERT) (*count)++;
    return out;
}

#endif /* QUEEN_CIFO_CACHE_H */
