// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * tx_duty.h — [FW.61] лімітер робочого циклу TX Королеви: не більше 1 %
 * ефіру в БУДЬ-ЯКУ годину.
 *
 * ЧОМУ. Умови НКЕК для SRD 868.0–868.6 МГц (постанова № 361, рядки 104/112 —
 * docs/protocols/legal/certification_roadmap.md §2) дають робочий цикл < 1 %,
 * тобто ≤ 36 с передавання на годину. Королева сама по собі ефіру майже не
 * займає (маяк раз на 15 хв), але OTA-серія 8 КБ — це до 745 кадрів тіла +
 * 4 печатки по 165 мс ≈ 123 с, і рефлекторний постріл (03_02 §5) відповідає
 * чанком на КОЖЕН почутий uplink, а re-request Солдата — до 72 кадрів
 * поспіль. Пейсингу за робочим циклом у P2P-тракті не було взагалі.
 * ⚖️ Делеговано 2026-09-24 (certification_roadmap §3.2): OTA у пілоті —
 * «з програмним обмеженням ефірного часу шлюзу ≤ 36 с на годину»; цей файл і
 * є тим обмеженням, і без нього поле заяви до НКЕК мусило б казати «не
 * виконується».
 *
 * ЯК. Кільце з TX_DUTY_BUCKETS п'ятихвилинних кошиків ефіру (мс). Рішення
 * про кадр сумує ВСІ кошики — 60…65 хв історії — плюс сам кадр і порівнює
 * зі стелею класу. Це стеля для будь-якого КОВЗНОГО вікна, а не лише для
 * календарної години: кадри будь-якого годинного вікна лежать у тих самих
 * кошиках, які перевіряв останній із них. Ціна — до 5 хв зайвої історії:
 * лімітер суворіший за стелю, ніколи не м'якший.
 *
 * КЛАСИ. Маяк часу (TX_DUTY_BEACON) може брати весь бюджет; решта
 * (TX_DUTY_BULK — OTA-чанк, печатка, re-request, CMD-постріл) — бюджет мінус
 * резерв маяка. Інакше важка OTA-година лишала б рій без часу, а вартовий
 * дрейфу Солдата кликав би маяк, якому ніде стати.
 *
 * ⚠️ Стелі, оголошені вголос:
 *   · рахує лише P2P-кадри `main.c`; LoRaWAN-детур ARCH.34 (868.1/.3/.5 МГц)
 *     має власний MAC із власним робочим циклом EU868 і сюди не входить;
 *   · годинне вікно — з EN 300 220-1, не з тексту постанови; у стандарті не
 *     звірено (certification_roadmap §2.3);
 *   · журнал живе в RAM: ребут його обнуляє. Спалах через ребут обмежений
 *     тим, що OTA-буфер теж у RAM (після ребута OTA немає до нового фетчу), а
 *     маяк мовчить до першого CoAP-роздтрипа (`queen_unix_ts == 0`);
 *   · час — `HAL_GetTick` Королеви: вона не спить у STOP2, тож тік іде стінним
 *     часом; unsigned-віднімання переживає 49.7-добовий wrap, якщо лімітер
 *     питають частіше (маяк — раз на 15 хв).
 *
 * Pure C, без HAL — host-тести: firmware/test/test_tx_duty.c.
 */
#ifndef SILKEN_TX_DUTY_H
#define SILKEN_TX_DUTY_H

#include <stdint.h>
#include <string.h>

/* 1 % від години. Дзеркало стелі умов НКЕК (certification_roadmap §2) —
 * правити там, не тут. */
#define TX_DUTY_WINDOW_MS   3600000u
#define TX_DUTY_BUDGET_MS     36000u

#define TX_DUTY_BUCKET_MS    300000u  /* 5 хв */
#define TX_DUTY_BUCKETS          13u  /* 12 × 5 хв = година + поточний кошик */

/* Резерв маяка — [transitional] 10 % бюджету. Підстава: періодичний маяк
 * (4/год × 165 мс ≈ 0.66 с) плюс відповіді на hello cold-boot'у й зойки
 * вартового дрейфу (кожен перемотує такт маяка, 03_02 §5а) — ≈ 20 кадрів на
 * годину. Шлях апгрейду: виміряна частота hello в пілоті. Ціна: BULK-клас
 * має 32.4 с/год, тож OTA-серія 8 КБ триває щонайменше ~3.8 год. */
#define TX_DUTY_BEACON_RESERVE_MS 3600u

_Static_assert((TX_DUTY_BUCKETS - 1u) * TX_DUTY_BUCKET_MS >= TX_DUTY_WINDOW_MS,
               "tx_duty: кільце коротше за годину — стеля ковзного вікна не тримається");
_Static_assert(TX_DUTY_BEACON_RESERVE_MS < TX_DUTY_BUDGET_MS,
               "tx_duty: резерв маяка з'їв би весь бюджет");

typedef enum {
    TX_DUTY_BULK   = 0,  /* OTA · печатка · re-request · CMD */
    TX_DUTY_BEACON = 1   /* маяк часу — може брати весь бюджет */
} TxDutyClass;

typedef struct {
    uint32_t spent_ms[TX_DUTY_BUCKETS]; /* ефір по кошиках, мс */
    uint32_t bucket_start_ms;           /* тік початку поточного кошика */
    uint8_t  head;                      /* індекс поточного кошика */
    uint8_t  started;                   /* 0 = ще жодного звертання */
} TxDutyLedger;

static inline void Tx_Duty_Init(TxDutyLedger *l)
{
    memset(l, 0, sizeof(*l));
}

/* Прокрутити кільце до `now_ms`: кошики, чий час минув, звільняються. */
static inline void Tx_Duty_Advance(TxDutyLedger *l, uint32_t now_ms)
{
    if (!l->started) {
        l->bucket_start_ms = now_ms;
        l->started = 1u;
        return;
    }
    uint32_t elapsed = now_ms - l->bucket_start_ms;  /* wrap-safe */
    if (elapsed < TX_DUTY_BUCKET_MS) return;

    uint32_t steps = elapsed / TX_DUTY_BUCKET_MS;
    if (steps >= TX_DUTY_BUCKETS) {
        memset(l->spent_ms, 0, sizeof(l->spent_ms));
        l->head = 0u;
    } else {
        for (uint32_t i = 0; i < steps; i++) {
            l->head = (uint8_t)((l->head + 1u) % TX_DUTY_BUCKETS);
            l->spent_ms[l->head] = 0u;
        }
    }
    /* steps × BUCKET ≤ elapsed < 2^32 — множення не переповнюється. */
    l->bucket_start_ms += steps * TX_DUTY_BUCKET_MS;
}

/* Ефір за останні 60…65 хв, мс. */
static inline uint32_t Tx_Duty_Spent_Ms(TxDutyLedger *l, uint32_t now_ms)
{
    Tx_Duty_Advance(l, now_ms);
    uint32_t sum = 0u;
    for (uint32_t i = 0; i < TX_DUTY_BUCKETS; i++) sum += l->spent_ms[i];
    return sum;
}

/* 1 = кадр ефіром `air_ms` вміщається в стелю класу; нічого не списує. */
static inline int Tx_Duty_Allows(TxDutyLedger *l, uint32_t now_ms,
                                 uint32_t air_ms, TxDutyClass cls)
{
    uint32_t ceiling = (cls == TX_DUTY_BEACON)
                           ? TX_DUTY_BUDGET_MS
                           : TX_DUTY_BUDGET_MS - TX_DUTY_BEACON_RESERVE_MS;
    uint32_t spent = Tx_Duty_Spent_Ms(l, now_ms);
    return (air_ms <= ceiling) && (spent <= ceiling - air_ms);
}

/* Списати кадр, що ПІШОВ в ефір. Кличе той, хто щойно отримав Allows = 1. */
static inline void Tx_Duty_Charge(TxDutyLedger *l, uint32_t now_ms, uint32_t air_ms)
{
    Tx_Duty_Advance(l, now_ms);
    l->spent_ms[l->head] += air_ms;
}

#endif /* SILKEN_TX_DUTY_H */
