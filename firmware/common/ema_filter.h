// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * ema_filter.h — [FW.21] Пульс Солдата крізь EMA: delta_t (швидкість перезаряду) і vcap,
 * α = 2/10, ціла арифметика у фіксованій комі (delta_t × 100, vcap × 10), без FPU.
 *
 * One-Home: фільтр кличе firmware/soldier/main.c, а host-сюїта — цей самий код, не копію
 * (гоча firmware #19). Його delta_t-половина — вхід балів CCM-кадру («wire = вхід GP», E.63 (г)),
 * тож сервер дзеркалить теплу гілку EMA_Update у `Telemetry::EmaRecurrence` (SEC.42 (б), друга
 * вісь — узгодженість EMA з потоком сирих delta_t). Його спек (spec/services/telemetry/ema_recurrence_spec.rb)
 * читає α звідси, а golden-таблиці — з host-тесту: однобічна зміна арифметики червонить іншу сюїту.
 *
 * Стан спить у RTC backup: DR10 = delta_t_x100 (u32), DR12 = [valid:8 | count:8 | vcap_x10:16]
 * (карта — docs/03_01 §2, канон фільтра — §13). HAL-читання й запис регістрів лишаються в main.c;
 * тут — лише пакування слова DR12 і відновлення з двох слів.
 */

#ifndef SILKEN_EMA_FILTER_H
#define SILKEN_EMA_FILTER_H

#include <stdint.h>

#define EMA_ALPHA_NUM     2       // α = 2/10 = 0.2
#define EMA_ALPHA_DEN     10
#define EMA_VALID_MAGIC   0x45    // 'E' — маркер ініціалізованого фільтра
#define EMA_WARMUP_CYCLES 3       // зразків до довіри EMA
#define EMA_VCAP_X10_MASK 0xFFFFu // нижні 16 біт DR12 — упакований vcap_x10

typedef struct {
    uint32_t delta_t_x100; // EMA delta_t × 100 (0.01 с) — DR10
    uint32_t vcap_x10;     // EMA vcap × 10 (0.1 мВ), ≤ 55 000 — DR12 [15:0]
    uint8_t  valid;        // EMA_VALID_MAGIC після першого зразка — DR12 [31:24]
    uint8_t  count;        // насичений лічильник зразків @ 255 — DR12 [23:16]
} SilkenEma;

/*
 * Один новий зразок. Холодна гілка (немає маркера або нуль зразків) — EMA = зразок;
 * тепла — α-згладжування. Переповнення немає: delta_t, що доходить сюди, не довший за
 * DELTA_T_MAX_PLAUSIBLE_S (7 діб, main.c), тож 2·x100 + 8·x100 ≤ 10 × 60 480 000 < 2³²;
 * vcap обмежує реальний діапазон 0..5500 мВ.
 */
static inline void EMA_Update(SilkenEma *e, uint32_t raw_dt_sec, uint16_t raw_vcap_mv)
{
    uint32_t raw_dt_x100  = raw_dt_sec * 100u;
    uint32_t raw_vcap_x10 = (uint32_t)raw_vcap_mv * 10u;

    if (e->valid != EMA_VALID_MAGIC || e->count == 0) {
        e->delta_t_x100 = raw_dt_x100;
        e->vcap_x10     = raw_vcap_x10;
        e->valid        = EMA_VALID_MAGIC;
        e->count        = 1;
        return;
    }

    e->delta_t_x100 = (EMA_ALPHA_NUM * raw_dt_x100 +
                       (EMA_ALPHA_DEN - EMA_ALPHA_NUM) * e->delta_t_x100)
                      / EMA_ALPHA_DEN;
    e->vcap_x10     = (EMA_ALPHA_NUM * raw_vcap_x10 +
                       (EMA_ALPHA_DEN - EMA_ALPHA_NUM) * e->vcap_x10)
                      / EMA_ALPHA_DEN;
    if (e->count < 255) e->count++;
}

/*
 * [ARCH.102] Невимір у фільтр не йде: на сентинелі «не виміряно» стан лишається, яким був, —
 * інакше фільтр «прогрівся» б на сентинелі й віддавав число, за яким виміру не стояло.
 * vcap їде парою з delta_t: один зразок на пробудження.
 */
static inline void EMA_Feed(SilkenEma *e, uint32_t raw_dt_sec, uint16_t raw_vcap_mv,
                            uint32_t unknown)
{
    if (raw_dt_sec != unknown) EMA_Update(e, raw_dt_sec, raw_vcap_mv);
}

static inline uint32_t EMA_Get_DeltaT_Sec(const SilkenEma *e) { return e->delta_t_x100 / 100u; }
static inline uint16_t EMA_Get_Vcap_Mv(const SilkenEma *e)    { return (uint16_t)(e->vcap_x10 / 10u); }

/* Прогрівся — ≥ EMA_WARMUP_CYCLES зразків; доти споживач бере сентинел (delta_t) чи номінал (vcap). */
static inline uint8_t EMA_Is_Warmed_Up(const SilkenEma *e)
{
    return (e->valid == EMA_VALID_MAGIC) && (e->count >= EMA_WARMUP_CYCLES);
}

/* Слово DR12. Пишеться й холодний стан — на старті його впізнає відсутній маркер. */
static inline uint32_t EMA_Pack_Dr12(const SilkenEma *e)
{
    return ((uint32_t)e->valid << 24) |
           ((uint32_t)e->count << 16) |
           (e->vcap_x10 & EMA_VCAP_X10_MASK);
}

/*
 * Відновлення з DR10 і DR12. Без маркера — холодний стан (усе нуль), і EMA стане перший зразок;
 * функція гарантує його сама, а не покладається на нульовий стан викликача.
 */
static inline void EMA_Restore(SilkenEma *e, uint32_t dr10, uint32_t dr12)
{
    uint8_t v = (uint8_t)((dr12 >> 24) & 0xFFu);
    if (v != EMA_VALID_MAGIC) {
        e->delta_t_x100 = 0;
        e->vcap_x10     = 0;
        e->valid        = 0;
        e->count        = 0;
        return;
    }
    e->delta_t_x100 = dr10;
    e->vcap_x10     = dr12 & EMA_VCAP_X10_MASK;
    e->valid        = v;
    e->count        = (uint8_t)((dr12 >> 16) & 0xFFu);
}

#endif /* SILKEN_EMA_FILTER_H */
