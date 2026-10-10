// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * adc_convert.h — VREFINT-калібрована конверсія ADC-відліків у мілівольти
 * (One-Home: компілюється у Soldier-прошивку ТА host-тести — без копій).
 *
 * [FW.50] Доти Soldier трактував сирий 12-bit ADC-відлік (~1500) як
 * мілівольти НАПРЯМУ: пороги 2800/4000/4500 мВ, EMA, vcap_mv у mruby.
 * На залізі це означало, що RX-вікно (>2800) не відкриється НІКОЛИ, а
 * Vcap-енергогейт працює з фейкових величин. Тут — чиста математика
 * конверсії; жива розводка (окремий ADC-канал Vcap + резистивний дільник)
 * лишається hardware-гейтом (FW.50 👤, узгодити з 02_03 BQ25570).
 *
 * Формули (STM32WLE5, RM0461):
 *   VDDA       = VREFINT_CAL_MV × VREFINT_CAL / VREFINT_DATA
 *   V_pin(мВ)  = VDDA × ADC_DATA / 4095
 *   V_node(мВ) = V_pin × (R_top + R_bot) / R_bot      ← дільник, hardware
 *
 * VREFINT_CAL — заводська константа @0x1FFF75AA, на STM32WL зміряна при
 * Vref+ = 3.3 В і 30 °C (`VREFINT_CAL_VREF` = 3300 у вендорському
 * stm32wlxx_ll_adc.h; 3.0 В — це L4/G4, не WL: з ним кожен відлік VDDA
 * занижувався на ~9 %). Рівність із вендорською константою тримає
 * `_Static_assert` у soldier/main.c — його бачить ARM-лейн. У прошивці
 * читається як *(uint16_t*)ADC_VREFINT_CAL_ADDR; чисті функції беруть її
 * параметром, щоб host-тести лишались без апаратної адреси.
 */

#ifndef SILKEN_ADC_CONVERT_H
#define SILKEN_ADC_CONVERT_H

#include <stdint.h>

#define ADC_VREFINT_CAL_MV    3300u          /* мВ — Vref+ заводської каліброванки WL */
#define ADC_FULL_SCALE_12BIT  4095u          /* 2^12 − 1 */
#define ADC_VREFINT_CAL_ADDR  0x1FFF75AAUL   /* uint16_t factory cal (firmware-only) */

/* Реальна VDDA (мВ) з відліку каналу VREFINT та його заводської каліброванки. */
static inline uint16_t Adc_Vdda_Mv(uint16_t vrefint_raw, uint16_t vrefint_cal)
{
    if (vrefint_raw == 0u) return 0u;        /* ADC-збій → 0, не ділимо на нуль */
    return (uint16_t)(((uint32_t)ADC_VREFINT_CAL_MV * vrefint_cal) / vrefint_raw);
}

/* Напруга на піні (мВ) для сирого відліку, за зміряною опорною VDDA. */
static inline uint16_t Adc_Pin_Mv(uint16_t adc_raw, uint16_t vdda_mv)
{
    return (uint16_t)(((uint32_t)vdda_mv * adc_raw) / ADC_FULL_SCALE_12BIT);
}

/*
 * Повний ланцюг: сирий відлік → реальна напруга вузла (мВ), VREFINT-калібрована
 * й повернена через резистивний дільник. div_num/div_den = (R_top+R_bot)/R_bot —
 * HARDWARE-залежні (FW.50: номінали ще не обрано — приклад 33 к / 47 к у
 * 02_01 §7.1, у 02_03 §5 їх внесе розводка), тому ПАРАМЕТР, а не
 * запечена константа (без передчасного канону). Прямий канал без дільника:
 * div_num = div_den = 1.
 */
static inline uint16_t Adc_Raw_To_Mv(uint16_t adc_raw, uint16_t vrefint_raw,
                                     uint16_t vrefint_cal,
                                     uint16_t div_num, uint16_t div_den)
{
    if (div_den == 0u) return 0u;
    uint32_t pin = (uint32_t)Adc_Pin_Mv(adc_raw, Adc_Vdda_Mv(vrefint_raw, vrefint_cal));
    return (uint16_t)((pin * div_num) / div_den);
}

/* [FW.50 · FW.66 (Б)] «Температуру не виміряно» — байт температури CCM-кадру на невдалому
 * відліку. INT8_MIN лежить поза будь-якою температурою MCU і поза межею розбору бекенду
 * (SAFE_TEMP_RANGE −45..90): бекенд розпізнає його ДО межі й пише NULL
 * (TelemetryUnpackerService::CCM_TEMP_UNMEASURED_C — дзеркало, рівність пінить спека). */
#define ADC_TEMP_UNMEASURED_C  (-128)

/* Вендорський макрос температури повертає це значення, коли заводська каліброванка
 * непридатна (TS_CAL1 == TS_CAL2), — теж невимір, а не +127 °C. Рівність із
 * LL_ADC_TEMPERATURE_CALC_ERROR тримає `_Static_assert` у firmware/soldier/main.c. */
#define ADC_TEMP_CALC_ERROR_C  0x7FFF

/* Байт температури для дроту. Невдалий відлік чи помилка обчислення — сентинел, а не °C,
 * які формула зробила б із сирого нуля (клас ARCH.102: фабрикація замість «не виміряно»).
 * Виміряне значення обрізається до [−127, 127], тож чесний вимір зі сентинелом не
 * збігається ніколи. */
static inline int8_t Adc_Temp_Wire_C(int read_ok, int32_t celsius)
{
    if (!read_ok || celsius == ADC_TEMP_CALC_ERROR_C) return (int8_t)ADC_TEMP_UNMEASURED_C;
    if (celsius < -127) return -127;
    if (celsius > 127) return 127;
    return (int8_t)celsius;
}

#endif /* SILKEN_ADC_CONVERT_H */
