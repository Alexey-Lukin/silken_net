// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * voc_maxhold.h — [HW.19] читання V_OC EBFC у MPPT-вікні BQ25570 без ключа
 *                 (One-Home, pure: Soldier-глю та host-тести компілюють цей код).
 *
 * Дерево, що хворіє, і іоністор, що старіє, виглядають однаково: `delta_t`
 * росте. Розрізнити їх може лише напруга розімкнутого кола EBFC (V_OC):
 * стоїть на власній базовій лінії вузла → старіє залізо, падає разом із
 * `delta_t` → стрес дерева (02_03 §12.4.2). Присуд founder 2026-09-10 — без
 * GPIO-розриву й без TPS22860: BQ25570 сам щось «дихає» — кожні 16 с на
 * 256 мс відʼєднує навантаження, щоб виміряти V_OC для MPPT (02_03 §3.2).
 * У цьому вікні `VIN_DC` ≈ V_OC, решту часу — робоча точка ROC × V_OC.
 * Отже max-hold над зразками `VIN_DC`, що ЩІЛЬНО вкривають ≥ один повний
 * MPPT-період, і є V_OC — ключа не треба.
 *
 * Цей модуль — арифметика вікна, і лише вона:
 *   1. вікно збору ≥ VOC_MAXHOLD_WINDOW_MIN_MS (≥ 16.3 с: період + відкрите
 *      вікно + запас), інакше MPPT-вікно могло не потрапити в збір;
 *   2. крок між зразками ≤ VOC_MAXHOLD_STEP_MAX_MS = половина відкритого
 *      вікна: тоді за будь-якої фази хоч один зразок лягає в ДРУГУ половину
 *      256 мс — а що пізніше в межах вікна взято зразок, то ближче він до
 *      V_OC (вхідна ємність дозаряджається через R_int 5–20 кΩ); max-hold
 *      бере найвищий, тобто найпізніший — і все одно недобирає: зсув
 *      0.35·V_OC·e^(−t/τ), τ = R_int·C_IN, росте зі старінням R_int
 *      (02_03 §12.4.2);
 *   3. проміжок, більший за крок, або час назад → збір ЗІПСОВАНО, і результат
 *      є сентинелом «не виміряно» (VOC_MV_UNKNOWN), а не «останнім кращим»:
 *      пропущене вікно дало б робочу точку (≈ 0.65 · V_OC) під виглядом V_OC —
 *      тихо занижений V_OC читався б як стрес дерева (ARCH.102-клас: підставлене
 *      число є фабрикацією, введений нуль — виміром).
 *
 * ⚠️ Стелі, названі вголос (гіпотеза за 00_06 §0 — фізику підтверджує стенд
 * після FW.46, 00_07 HW.19):
 *   - модуль не знає, чи мВ на вході справді з `VIN_DC` і чи ADC-канал уже
 *     розведений (`MX_ADC_Init` порожній) — це HAL-половина; конверсія
 *     відлік → мВ живе в adc_convert.h (`Adc_Raw_To_Mv`, дільник 1:1 —
 *     0.5–0.8 В < VDDA), тут лише мВ;
 *   - часова база — будь-які монотонні мілісекунди, які HAL-половина дає під
 *     час збору. `HAL_GetTick` у STOP2 стоїть (firmware #8), тож щільний збір
 *     на ≥ 16.3 с — LPTIM-пробудження: активне вікно виключене арифметикою
 *     (02_03 §9.8б, `tools/firmware/boot_brownout_cycle.rb`), а ціну одного
 *     пробудження проти її стелі міряє стенд (RUNBOOK §3.5);
 *   - «раз на добу» (02_03 §12.4.2) і доставка рідкісного сигналу — delivery-
 *     контракт: поле rev3 у слоті кадру без писача, не 0x57 (⚖️ 2026-10-01,
 *     ledger 03_05 §2.1); слот і ширину обирає пакет rev3 разом із FW.59, тож
 *     тут немає ані розкладу, ані дроту.
 *
 * 🚨 DCI-guard: V_OC НЕ входить у входи Атрактора Лоренца — корекція живе на
 * slashing-шарі (`ContractHealthCheckService`), інакше server-Z ≠ device-Z.
 * Канон: 02_03 §12.4.2 (концепт + DCI-safe архітектура) · 02_03 §3.2 (MPPT-
 * вікно) · 00_07 HW.19.
 */
#ifndef SILKEN_VOC_MAXHOLD_H
#define SILKEN_VOC_MAXHOLD_H

#include <stdint.h>

/* MPPT-семплінг BQ25570 — датащит, дзеркало 02_03 §3.2 (правити ТАМ). */
#define VOC_MPPT_PERIOD_MS          16000u
#define VOC_MPPT_OPEN_MS              256u

/* Мінімальне вікно збору: період + відкрите вікно + запас (канон «≥ 16.3 с»). */
#define VOC_MAXHOLD_WINDOW_MIN_MS   16300u
/* Найбільший дозволений крок між зразками: половина відкритого вікна. */
#define VOC_MAXHOLD_STEP_MAX_MS     (VOC_MPPT_OPEN_MS / 2u)

_Static_assert(VOC_MAXHOLD_WINDOW_MIN_MS >= VOC_MPPT_PERIOD_MS + VOC_MPPT_OPEN_MS,
               "вікно збору мусить вкривати повний MPPT-період плюс відкрите вікно");
_Static_assert(VOC_MAXHOLD_STEP_MAX_MS * 2u <= VOC_MPPT_OPEN_MS,
               "крок мусить гарантувати зразок у другій половині відкритого вікна");

/* Сентинел «не виміряно». Реальний замір сатурується до ≥ 1 мВ, щоб не
 * зіткнутися з ним (прецедент BME280_VPD_INDEX_MIN). */
#define VOC_MV_UNKNOWN              0u
#define VOC_MV_MIN                  1u

/* Коди Voc_MaxHold_Feed / _Init. */
#define VOC_MAXHOLD_PENDING         0   /* вікно ще збирається */
#define VOC_MAXHOLD_DONE            1   /* вікно минуло — результат чинний і ОСТАТОЧНИЙ */
#define VOC_MAXHOLD_ERR_GAP       (-1)  /* проміжок > STEP_MAX: MPPT-вікно могло проскочити */
#define VOC_MAXHOLD_ERR_TIME      (-2)  /* час пішов назад */
#define VOC_MAXHOLD_ERR_WINDOW    (-3)  /* запитане вікно коротше за мінімум */

typedef struct {
    uint32_t window_ms;   /* ≥ VOC_MAXHOLD_WINDOW_MIN_MS */
    uint32_t t0_ms;       /* час першого зразка */
    uint32_t last_ms;     /* час останнього прийнятого зразка */
    uint16_t max_mv;      /* найвищий зразок (сатурований до ≥ VOC_MV_MIN) */
    uint16_t samples;     /* прийнятих зразків, сатурується на UINT16_MAX */
    uint8_t  state;       /* VOC_MAXHOLD_ST_* */
} VocMaxHold;

#define VOC_MAXHOLD_ST_EMPTY        0u
#define VOC_MAXHOLD_ST_COLLECTING   1u
#define VOC_MAXHOLD_ST_DONE         2u
#define VOC_MAXHOLD_ST_SPOILED      3u

/* Готує збір. Вікно коротше за мінімум → ERR_WINDOW, і об'єкт зіпсовано:
 * жоден Feed далі не дасть результату (не «найкраще, що є»). */
static inline int Voc_MaxHold_Init(VocMaxHold *s, uint32_t window_ms)
{
    s->window_ms = window_ms;
    s->t0_ms = 0u;
    s->last_ms = 0u;
    s->max_mv = VOC_MV_UNKNOWN;
    s->samples = 0u;
    if (window_ms < VOC_MAXHOLD_WINDOW_MIN_MS) {
        s->state = VOC_MAXHOLD_ST_SPOILED;
        return VOC_MAXHOLD_ERR_WINDOW;
    }
    s->state = VOC_MAXHOLD_ST_EMPTY;
    return VOC_MAXHOLD_PENDING;
}

/* Один зразок `VIN_DC` у мВ на момент now_ms. Після DONE об'єкт остаточний:
 * подальші зразки ігноруються (результат — знімок вікна, не рухома величина). */
static inline int Voc_MaxHold_Feed(VocMaxHold *s, uint32_t now_ms, uint16_t mv)
{
    if (s->state == VOC_MAXHOLD_ST_SPOILED) return VOC_MAXHOLD_ERR_GAP;
    if (s->state == VOC_MAXHOLD_ST_DONE)    return VOC_MAXHOLD_DONE;

    if (mv < VOC_MV_MIN) mv = VOC_MV_MIN;

    if (s->state == VOC_MAXHOLD_ST_EMPTY) {
        s->t0_ms = now_ms;
        s->last_ms = now_ms;
        s->max_mv = mv;
        s->samples = 1u;
        s->state = VOC_MAXHOLD_ST_COLLECTING;
        return VOC_MAXHOLD_PENDING;
    }

    if (now_ms < s->last_ms) {
        s->state = VOC_MAXHOLD_ST_SPOILED;
        return VOC_MAXHOLD_ERR_TIME;
    }
    if (now_ms - s->last_ms > VOC_MAXHOLD_STEP_MAX_MS) {
        s->state = VOC_MAXHOLD_ST_SPOILED;
        return VOC_MAXHOLD_ERR_GAP;
    }

    s->last_ms = now_ms;
    if (mv > s->max_mv) s->max_mv = mv;
    if (s->samples < UINT16_MAX) s->samples++;

    if (now_ms - s->t0_ms >= s->window_ms) {
        s->state = VOC_MAXHOLD_ST_DONE;
        return VOC_MAXHOLD_DONE;
    }
    return VOC_MAXHOLD_PENDING;
}

/* V_OC у мВ, лише коли вікно зібрано цілком і без розривів; інакше сентинел. */
static inline uint16_t Voc_MaxHold_Result(const VocMaxHold *s)
{
    return (s->state == VOC_MAXHOLD_ST_DONE) ? s->max_mv : (uint16_t)VOC_MV_UNKNOWN;
}

#endif /* SILKEN_VOC_MAXHOLD_H */
