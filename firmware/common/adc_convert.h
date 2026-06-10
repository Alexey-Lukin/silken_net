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
 * VREFINT_CAL — заводська константа @0x1FFF75AA (зміряна при VDDA = 3.0 В,
 * 30 °C). У прошивці читається як *(uint16_t*)ADC_VREFINT_CAL_ADDR; чисті
 * функції беруть її параметром, щоб host-тести лишались без апаратної адреси.
 */

#ifndef SILKEN_ADC_CONVERT_H
#define SILKEN_ADC_CONVERT_H

#include <stdint.h>

#define ADC_VREFINT_CAL_MV    3000u          /* мВ — VDDA при заводській каліброванці */
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
 * HARDWARE-залежні (FW.50 👤, номінали TBD з 02_03), тому ПАРАМЕТР, а не
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

#endif /* SILKEN_ADC_CONVERT_H */
