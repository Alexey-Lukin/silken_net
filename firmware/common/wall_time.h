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
 *   - cold-start (last == 0): попереднього циклу не було → baseline;
 *   - назад (now < last): годинник зсунули назад / RTC-аномалія → baseline;
 *   - неправдоподібно вперед (> max_plausible): календар щойно виставлено з
 *     beacon-UTC (стрибок епохи) або wrap → baseline (наступний цикл зміряє
 *     справжню різницю);
 *   - інакше: now − last.
 * baseline та max_plausible передаються параметром, щоб хедер лишався
 * config-free (значення живуть у викликачеві: BASELINE_DELTA_T_S тощо).
 */
static inline uint32_t Silken_Wall_Delta_Seconds(uint32_t wall_now, uint32_t last_wall,
                                                 uint32_t baseline, uint32_t max_plausible)
{
    if (last_wall == 0u)       return baseline;   /* cold-start: немає попереднього */
    if (wall_now < last_wall)  return baseline;   /* зсув назад */
    uint32_t d = wall_now - last_wall;
    if (d > max_plausible)     return baseline;   /* стрибок епохи / wrap */
    return d;
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
