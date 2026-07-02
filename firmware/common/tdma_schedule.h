/*
 * tdma_schedule.h — [ARCH.26 L2] слот-розкладка синхронних TDMA-вікон
 * (One-Home: Queen пакує байти 5..8 маяка, Soldier парсить, host-тести
 * компілюють цей самий код — без копій).
 *
 * Проблема Рандеву (03_01 §1.9): Солдат між пробудженнями глухий, пакет
 * у порожнє вухо розчиняється в ефірі. L2 = спільний розклад коротких
 * синхронних вікон, який Королева оголошує у TDMA-резерві Time Beacon
 * (байти 5..8 — wire-дім 03_02 §5а.2). Вікно відкривається коли
 * unix_ts % period == phase; всередині — slot_count TX-слотів, слот
 * вузла = DID % slot_count (детерміновано, без реєстрації у Королеви).
 *
 * Енерго-політика ролей (03_01 §1.9, канон-корекція 2026-05-28): повний
 * RX у кожному вікні (~30 мДж) — привілей Провідника (ARCH.27); рядовий
 * Солдат використовує розклад лише як TX-таймінг (slotted uplink,
 * FW.27-A) та майбутній L3 CAD-нюх. Це рахувальний хедер — він каже
 * КОЛИ, а не змушує слухати.
 *
 * Стеля точності (позначена, 03_02 §5а.2): маяк несе цілі секунди →
 * фазова похибка вузла ≈ ±1 с. Слоти коротші за ~2 с розкидають
 * популяцію статистично (фазові групи + jitter), а не ізолюють
 * детерміновано; апгрейд = ts_frac у байті 11 маяка (1/256 с).
 */

#ifndef SILKEN_TDMA_SCHEDULE_H
#define SILKEN_TDMA_SCHEDULE_H

#include <stdint.h>

/* Wire-кванти байтів 5..8 (канон 03_02 §5а.2) */
#define TDMA_WIRE_WINDOW_QUANTUM_MS  100u
#define TDMA_WIRE_PHASE_QUANTUM_S    4u

/* Розгорнутий розклад (host-байтова структура, НЕ wire-формат). */
typedef struct {
    uint16_t period_s;    /* період вікон, сек; 0 = TDMA вимкнено */
    uint16_t window_ms;   /* довжина вікна, мс */
    uint8_t  slot_count;  /* TX-слоти у вікні; 0 = unslotted (listen-only) */
    uint16_t phase_s;     /* зсув сітки від epoch-межі періоду, сек */
} TdmaSchedule;

static inline uint8_t Tdma_Enabled(const TdmaSchedule *s)
{
    return (uint8_t)(s->period_s != 0u);
}

/*
 * Queen-сторона: пакує розклад у 4 wire-байти (маяк, позиції 5..8).
 * Параметри вже у wire-одиницях — Королева тримає їх константами.
 * period_min == 0 легально означає «TDMA off» (нинішній нульовий ефір).
 */
static inline void Tdma_Pack_Beacon_Bytes(uint8_t period_min, uint8_t window_100ms,
                                          uint8_t slot_count, uint8_t phase_4s,
                                          uint8_t out[4])
{
    out[0] = period_min;
    out[1] = window_100ms;
    out[2] = slot_count;
    out[3] = phase_4s;
}

/*
 * Soldier-сторона: парсить wire-байти 5..8 у розклад. Fail-closed:
 * будь-яка беззмістовна комбінація (нульовий period — легальний off;
 * нульове вікно чи фаза поза періодом — сміття/бітфліп) → disabled,
 * повертає 0. Валідний увімкнений розклад → 1.
 */
static inline uint8_t Tdma_Parse_Beacon_Bytes(const uint8_t in[4], TdmaSchedule *out)
{
    out->period_s   = 0u;
    out->window_ms  = 0u;
    out->slot_count = 0u;
    out->phase_s    = 0u;

    if (in[0] == 0u) return 0u;                       /* TDMA off — легальний wire */

    uint32_t period_s  = (uint32_t)in[0] * 60u;
    uint32_t window_ms = (uint32_t)in[1] * TDMA_WIRE_WINDOW_QUANTUM_MS;
    uint32_t phase_s   = (uint32_t)in[3] * TDMA_WIRE_PHASE_QUANTUM_S;

    if (window_ms == 0u)      return 0u;              /* вікно нульової довжини */
    if (phase_s >= period_s)  return 0u;              /* фаза поза періодом */

    out->period_s   = (uint16_t)period_s;             /* ≤ 15300 — влазить */
    out->window_ms  = (uint16_t)window_ms;            /* ≤ 25500 — влазить */
    out->slot_count = in[2];
    out->phase_s    = (uint16_t)phase_s;
    return 1u;
}

/*
 * Наступний старт вікна СТРОГО ПІСЛЯ unix_now (для WUT-армінгу потрібен
 * майбутній момент; «чи вікно вже йде зараз» питають у Tdma_In_Window).
 * 0 = розклад вимкнено (сентінель у дусі wall_time «0 = не виставлено»).
 */
static inline uint32_t Tdma_Next_Window_Start(const TdmaSchedule *s, uint32_t unix_now)
{
    if (!Tdma_Enabled(s)) return 0u;
    uint32_t period      = s->period_s;
    uint32_t cycle_start = unix_now - (unix_now % period);
    uint32_t cand        = cycle_start + s->phase_s;
    if (cand <= unix_now) cand += period;
    return cand;
}

/* Чи відкрите вікно у момент unix_now: [start, start + window_ms). */
static inline uint8_t Tdma_In_Window(const TdmaSchedule *s, uint32_t unix_now)
{
    if (!Tdma_Enabled(s)) return 0u;
    uint32_t period = s->period_s;
    uint32_t off_s  = (unix_now % period + period - (uint32_t)s->phase_s) % period;
    return (uint8_t)((off_s * 1000u) < (uint32_t)s->window_ms);
}

/*
 * TX-слот вузла у вікні — детерміновано від DID, без реєстрації.
 * slot_count == 0 (unslotted) → слот 0, offset 0: шли на старті вікна.
 */
static inline uint8_t Tdma_Slot_For_Did(const TdmaSchedule *s, uint32_t did)
{
    if (!Tdma_Enabled(s) || s->slot_count == 0u) return 0u;
    return (uint8_t)(did % s->slot_count);
}

/* Зсув TX від старту вікна, мс. Precondition: slot < slot_count. */
static inline uint16_t Tdma_Slot_Tx_Offset_Ms(const TdmaSchedule *s, uint8_t slot)
{
    if (!Tdma_Enabled(s) || s->slot_count == 0u) return 0u;
    return (uint16_t)(((uint32_t)s->window_ms * slot) / s->slot_count);
}

#endif /* SILKEN_TDMA_SCHEDULE_H */
