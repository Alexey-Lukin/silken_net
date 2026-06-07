/*
 * wall_time.h — wall-clock delta/elapsed helpers (One-Home: Soldier firmware
 * ТА host-тести компілюють цей самий код — без копій).
 *
 * [FW.49] `HAL_GetTick()` (SysTick) заморожений у STOP2 → будь-яка tick-різниця
 * міряє лише active-час циклу, а НЕ wall-інтервал між пробудженнями. Це
 * фальсифікувало delta_t (первинний біосигнал метаболізму): active-час ~секунди
 * → β-пертурбація притиснута біля максимуму → усі дерева «максимально здорові»
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

#endif /* SILKEN_WALL_TIME_H */
