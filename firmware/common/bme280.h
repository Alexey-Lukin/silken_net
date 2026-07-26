// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * bme280.h — [HW.32] кліматичне чуття Солдата: компенсація BME280 +
 *            квантизація VPD-confounder'а (One-Home, pure).
 *
 * Дерево не вміє брехати про погоду. Падіння сокоруху (`delta_t`) під
 * дощем — це фізика, не хвороба: насичене повітря (RH≈100%) знімає тягу
 * ксилеми. Без цього сенсора мережа сліпа й може спалити токени за здорове
 * дерево (False Slashing, 05_05 §6/§7). VPD (Vapor Pressure Deficit) —
 * прямий фізіологічний confounder: рахуємо його НА вузлі з t°+RH і шлемо
 * одним байтом, щоб бекенд не штрафував за погоду.
 *
 * Цей модуль — чиста математика, без I²C/HAL (драйвер читання — bench):
 *   1. Bme280_Compensate_*  — фіксована-точка з datasheet Bosch §8.2
 *      (int32 T → °C×100; int64 P → Pa Q24.8; int32 H → %RH Q22.10).
 *      Host-тест звіряє цілочисельний шлях проти НЕЗАЛЕЖНОЇ float-копії
 *      тієї ж формули (дві транскрипції datasheet мусять зійтися —
 *      некругова golden, test_bme280.c).
 *   2. Bme280_Vpd_Index     — SVP за FAO-56 (Tetens), VPD = SVP·(1−RH/100),
 *      квантизація 0.02 kPa/LSB. 0x00 ЗАРЕЗЕРВОВАНО = «немає BME280»;
 *      реальний замір сатурується до ≥1, щоб не зіткнутися з сентинелем.
 *
 * 🚨 DCI-guard: VPD НЕ входить у входи Атрактора Лоренца (ті —
 * temp/acoustic/delta_t/vcap) → firmware↔backend bit-identity не зачіпається.
 * VPD живе виключно на confounder/slashing-шарі (03_04 DCI).
 *
 * Дріт: байт 19 `vpd_index` CCM wire-rev2 (03_05 §2.1 wire-budget ledger; lora_ccm.h).
 * Канон: 02_01 §3.4 (ADR + VPD-формула) · 03_01 SENSE · 05_05 §6/§7 · 00_07 HW.32.
 */
#ifndef SILKEN_BME280_H
#define SILKEN_BME280_H

#include <stdint.h>
#include <math.h>

/* Калібрувальні коефіцієнти NVM BME280 (datasheet §4.2.2). Зчитуються
 * один раз при bring-up з регістрів 0x88..0xA1 / 0xE1..0xE7. */
typedef struct {
    uint16_t dig_T1;
    int16_t  dig_T2, dig_T3;
    uint16_t dig_P1;
    int16_t  dig_P2, dig_P3, dig_P4, dig_P5, dig_P6, dig_P7, dig_P8, dig_P9;
    uint8_t  dig_H1;
    int16_t  dig_H2;
    uint8_t  dig_H3;
    int16_t  dig_H4, dig_H5;
    int8_t   dig_H6;
} Bme280_Calib;

/* Температура: сирий 20-біт adc_T → °C×100 ("5123" = 51.23 °C).
 * Side-effect: повертає t_fine (несе «тонку» температуру для P та H). */
static inline int32_t Bme280_Compensate_T(const Bme280_Calib *c, int32_t adc_T,
                                          int32_t *t_fine_out)
{
    int32_t var1 = ((((adc_T >> 3) - ((int32_t)c->dig_T1 << 1))) *
                    ((int32_t)c->dig_T2)) >> 11;
    int32_t var2 = (((((adc_T >> 4) - ((int32_t)c->dig_T1)) *
                      ((adc_T >> 4) - ((int32_t)c->dig_T1))) >> 12) *
                    ((int32_t)c->dig_T3)) >> 14;
    int32_t t_fine = var1 + var2;
    *t_fine_out = t_fine;
    return (t_fine * 5 + 128) >> 8;
}

/* Тиск: сирий 20-біт adc_P + t_fine → Pa у Q24.8 ("24674867" = 96386.2 Pa).
 * 0 = чисельна сингулярність (var1==0) — викликач трактує як «недійсно». */
static inline uint32_t Bme280_Compensate_P(const Bme280_Calib *c, int32_t adc_P,
                                          int32_t t_fine)
{
    int64_t var1 = ((int64_t)t_fine) - 128000;
    int64_t var2 = var1 * var1 * (int64_t)c->dig_P6;
    var2 = var2 + ((var1 * (int64_t)c->dig_P5) << 17);
    var2 = var2 + (((int64_t)c->dig_P4) << 35);
    var1 = ((var1 * var1 * (int64_t)c->dig_P3) >> 8) +
           ((var1 * (int64_t)c->dig_P2) << 12);
    var1 = (((((int64_t)1) << 47) + var1)) * ((int64_t)c->dig_P1) >> 33;
    if (var1 == 0) {
        return 0; /* уникаємо ділення на нуль */
    }
    int64_t p = 1048576 - adc_P;
    p = (((p << 31) - var2) * 3125) / var1;
    var1 = (((int64_t)c->dig_P9) * (p >> 13) * (p >> 13)) >> 25;
    var2 = (((int64_t)c->dig_P8) * p) >> 19;
    p = ((p + var1 + var2) >> 8) + (((int64_t)c->dig_P7) << 4);
    return (uint32_t)p;
}

/* Вологість: сирий 16-біт adc_H + t_fine → %RH у Q22.10 ("47445" = 46.33 %RH). */
static inline uint32_t Bme280_Compensate_H(const Bme280_Calib *c, int32_t adc_H,
                                          int32_t t_fine)
{
    int32_t v = (t_fine - ((int32_t)76800));
    v = (((((adc_H << 14) - (((int32_t)c->dig_H4) << 20) -
            (((int32_t)c->dig_H5) * v)) + ((int32_t)16384)) >> 15) *
         (((((((v * ((int32_t)c->dig_H6)) >> 10) *
             (((v * ((int32_t)c->dig_H3)) >> 11) + ((int32_t)32768))) >> 10) +
            ((int32_t)2097152)) * ((int32_t)c->dig_H2) + 8192) >> 14));
    v = (v - (((((v >> 15) * (v >> 15)) >> 7) * ((int32_t)c->dig_H1)) >> 4));
    v = (v < 0 ? 0 : v);
    v = (v > 419430400 ? 419430400 : v);
    return (uint32_t)(v >> 12);
}

/* ── VPD ─────────────────────────────────────────────────────────────────
 * SVP за FAO-56 Allen et al. 1998 (Tetens, eq. 11):
 *   e_s(T) = 0.6108 · exp(17.27·T / (T + 237.3))   [kPa], T у °C
 *   VPD    = e_s(T) · (1 − RH/100)                  [kPa]
 * Квантизація: index = round(VPD / 0.02 kPa).  Шкала калібрується bench'ем
 * проти референсного гігрометра — це канонічна СТЕЛЯ (0..5.1 kPa @ 0.02/LSB),
 * але самий index→kPa мапінг фіналізується при калібруванні (02_01 §3.4).
 *
 * 0x00 зарезервований під «немає BME280» (call-site шле літерал). Реальний
 * замір сатурується до [1..255] — навіть VPD≈0 (насичене повітря) дає 1,
 * щоб не злитися з сентинелем «сенсора нема». */
#define BME280_VPD_KPA_PER_LSB   0.02
#define BME280_VPD_INDEX_MIN     1u   /* 0x00 = «немає сенсора» */
#define BME280_VPD_INDEX_MAX     255u /* 255·0.02 = 5.1 kPa стеля */

static inline double Bme280_Saturation_Vapor_Pressure_kPa(double temp_c)
{
    return 0.6108 * exp(17.27 * temp_c / (temp_c + 237.3));
}

/* (temp_c, rh_pct) → байт VPD-індексу. Сенсор присутній ⇒ ∈ [1..255]. */
static inline uint8_t Bme280_Vpd_Index(double temp_c, double rh_pct)
{
    double rh = rh_pct < 0.0 ? 0.0 : (rh_pct > 100.0 ? 100.0 : rh_pct);
    double vpd = Bme280_Saturation_Vapor_Pressure_kPa(temp_c) * (1.0 - rh / 100.0);
    if (vpd < 0.0) {
        vpd = 0.0; /* інверсія/туман — тяги немає */
    }
    long idx = lround(vpd / BME280_VPD_KPA_PER_LSB);
    if (idx < (long)BME280_VPD_INDEX_MIN) {
        idx = (long)BME280_VPD_INDEX_MIN;
    } else if (idx > (long)BME280_VPD_INDEX_MAX) {
        idx = (long)BME280_VPD_INDEX_MAX;
    }
    return (uint8_t)idx;
}

/* Зручний міст від компенсованих цілих (°C×100, %RH Q22.10) до VPD-байта —
 * рівно те, що SENSE має на руках після Bme280_Compensate_T/H. */
static inline uint8_t Bme280_Vpd_Index_From_Compensated(int32_t temp_centi_c,
                                                        uint32_t rh_q10)
{
    return Bme280_Vpd_Index((double)temp_centi_c / 100.0,
                            (double)rh_q10 / 1024.0);
}

#endif /* SILKEN_BME280_H */
