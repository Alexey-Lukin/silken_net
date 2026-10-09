// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * wall_time.h — wall-clock delta/elapsed helpers (One-Home: Soldier firmware
 * ТА host-тести компілюють цей самий код — без копій).
 *
 * [FW.49] `HAL_GetTick()` (SysTick) заморожений у STOP2 → будь-яка tick-різниця
 * міряє лише active-час циклу, а НЕ wall-інтервал між пробудженнями. Це
 * фальсифікувало delta_t (первинний біосигнал метаболізму): active-час ~секунди
 * → метаболічний бал m(delta_t) притиснутий біля максимуму → усі дерева «максимально здорові»
 * → over-mint. Лік — читати free-running RTC-календар (LSE йде у STOP2) як
 * wall-секунди, а різницю рахувати через guard'и тут. Чиста арифметика, без HAL.
 *
 * Канон wake-семантики/часу — `03_01 §1.10` + `00_07` FW.49.
 */

#ifndef SILKEN_WALL_TIME_H
#define SILKEN_WALL_TIME_H

#include <stdint.h>

/*
 * delta_t між двома відліками wall-секунд із захистами:
 *   - cold-start (last == 0): попереднього циклу не було → unknown;
 *   - назад (now < last): годинник зсунули назад / RTC-аномалія → unknown;
 *   - неправдоподібно вперед (> max_plausible): календар щойно виставлено з
 *     beacon-UTC (стрибок епохи) або wrap → unknown (наступний цикл зміряє
 *     справжню різницю);
 *   - інакше: now − last.
 * unknown та max_plausible передаються параметром, щоб хедер лишався
 * config-free. Солдат передає сентинел «не виміряно» DELTA_T_UNKNOWN_S
 * (ARCH.102): «нейтральні» 60 с, що стояли тут доти, mruby мапить у
 * growth_points = МАКСИМУМ, тож відмова виміряти мінтила б найбільше.
 */
static inline uint32_t Silken_Wall_Delta_Seconds(uint32_t wall_now, uint32_t last_wall,
                                                 uint32_t unknown, uint32_t max_plausible)
{
    if (last_wall == 0u)       return unknown;    /* cold-start: немає попереднього */
    if (wall_now < last_wall)  return unknown;    /* зсув назад */
    uint32_t d = wall_now - last_wall;
    if (d > max_plausible)     return unknown;    /* стрибок епохи / wrap */
    return d;
}

/*
 * delta_t пробудження: кожне пробудження рухає базу на свій wall-відлік.
 */
static inline uint32_t Silken_Wake_Delta_Seconds(uint32_t wall_now, uint32_t *base_wall,
                                                 uint32_t unknown, uint32_t max_plausible)
{
    uint32_t d = Silken_Wall_Delta_Seconds(wall_now, *base_wall, unknown, max_plausible);
    *base_wall = wall_now;
    return d;
}

/*
 * Що йде в mruby і на дріт як вхід балів (контракт «wire = вхід GP», E.63 (г)):
 * EMA — лише прогріта, інакше сентинел (пара status 0 / GP 0 — 03_04 §4.3).
 * Сатурація u16 — ширина поля на дроті.
 */
static inline uint32_t Silken_Wake_Lorenz_Delta_T(uint8_t ema_warm, uint32_t ema_s,
                                                  uint32_t unknown)
{
    if (!ema_warm) return unknown;
    return (ema_s > 0xFFFFu) ? 0xFFFFu : ema_s;
}

/*
 * Скільки wall-секунд минуло від маркера (0 = маркер ще не виставлено → 0).
 * Monotonic-safe: зсув назад → 0. Для тривалостей-сторожів (FW.20-S2 drift
 * «давно не чули Королеву», FW.27-B «тиша у ефірі»), які раніше стояли на tick.
 */
static inline uint32_t Silken_Wall_Elapsed_Seconds(uint32_t wall_now, uint32_t since_wall)
{
    if (since_wall == 0u)      return 0u;   /* маркер не виставлено */
    if (wall_now < since_wall) return 0u;   /* зсув назад */
    return wall_now - since_wall;
}

/*
 * [SEC.42] Межа кроку годинника НАЗАД за маяком часу: підлога (ціла секунда маяка й
 * латентність ефіру) + дрейф LSE від останнього синку. 50 ppm — у 2.5× ширше за допуск
 * кварцу (±20 ppm), тож чесний Солдат у межу не впирається за будь-якого проміжку синку.
 */
#define SILKEN_BEACON_BACKSTEP_FLOOR_S    2u
#define SILKEN_BEACON_BACKSTEP_DRIFT_DIV  20000u   /* 1 с на 20 000 с = 50 ppm */

/*
 * [SEC.42] Куди ставити календар за маяком часу (03_05 §2.4). Уперед — як є: повтор дає
 * лише старі мітки, а майбутньої без KEYB не підробити. Назад — не далі за межу вище:
 * більший крок КЛЕМПИТЬСЯ до неї, а не ігнорується, тож Солдат, що побіг уперед,
 * сходиться до UTC, а повтор маяка вкорочує наступний delta_t щонайбільше на межу.
 * since_sync_wall — мітка останнього синку в часі календаря (0 = синку не було або
 * стан загублено → лише підлога). wall_now = 0 (RTC не прочитано) → маяк як є.
 */
static inline uint32_t Silken_Beacon_Clock_Target(uint32_t wall_now, uint32_t beacon_ts,
                                                  uint32_t since_sync_wall)
{
    if (beacon_ts >= wall_now) return beacon_ts;
    uint32_t max_back = SILKEN_BEACON_BACKSTEP_FLOOR_S +
        Silken_Wall_Elapsed_Seconds(wall_now, since_sync_wall) / SILKEN_BEACON_BACKSTEP_DRIFT_DIV;
    uint32_t back = wall_now - beacon_ts;
    return (back <= max_back) ? beacon_ts : (wall_now - max_back);
}

/*
 * [FW.49 S1] Чи несе wall-значення справжній UTC? Незсинхований календар
 * біжить від RTC-default 2000-01-01 (946684800) — щоб перетнути цей поріг
 * (2020-09) без time-sync, вузол мусив би пропрацювати ~20 років. Дельтам
 * UTC не потрібен (календар free-running і так); абсолютність потрібна
 * epoch_day (SEC.11 cold-start деривація).
 */
#define SILKEN_WALL_UTC_MIN 1600000000u

static inline uint8_t Silken_Wall_Is_Utc(uint32_t wall_seconds)
{
    return (uint8_t)(wall_seconds >= SILKEN_WALL_UTC_MIN);
}

/*
 * [FW.49 S1] unix-секунди → громадянський календар (інверсія, civil_from_days
 * Говарда Гіннанта). Пряма функція — `lorenz_seed.h` Silken_Days_From_Civil /
 * Silken_Unix_From_Calendar (FW.30, One-Home прямого напрямку); пару тримають
 * roundtrip host-тести — розійтись мовчки не можуть. Споживач: запис
 * beacon-UTC у RTC-календар (HAL_RTC_SetDate/SetTime BIN), після чого
 * календар = абсолютний timebase для delta_t/epoch_day.
 */
static inline void Silken_Civil_From_Unix(uint32_t unix_ts,
                                          int32_t *year, uint32_t *month, uint32_t *day,
                                          uint32_t *hh, uint32_t *mm, uint32_t *ss)
{
    uint32_t secs_of_day = unix_ts % 86400u;
    *hh = secs_of_day / 3600u;
    *mm = (secs_of_day % 3600u) / 60u;
    *ss = secs_of_day % 60u;

    int32_t  z   = (int32_t)(unix_ts / 86400u) + 719468;
    int32_t  era = (z >= 0 ? z : z - 146096) / 146097;
    uint32_t doe = (uint32_t)(z - era * 146097);                              /* [0, 146096] */
    uint32_t yoe = (doe - doe / 1460u + doe / 36524u - doe / 146096u) / 365u; /* [0, 399] */
    int32_t  y   = (int32_t)yoe + era * 400;
    uint32_t doy = doe - (365u * yoe + yoe / 4u - yoe / 100u);                /* [0, 365] */
    uint32_t mp  = (5u * doy + 2u) / 153u;                                    /* [0, 11] */
    *day   = doy - (153u * mp + 2u) / 5u + 1u;                                /* [1, 31] */
    *month = (mp < 10u) ? (mp + 3u) : (mp - 9u);                              /* [1, 12] */
    *year  = y + ((*month <= 2u) ? 1 : 0);
}

#endif /* SILKEN_WALL_TIME_H */
