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
 * Цей модуль pure, без HAL (I²C-глю й живе читання — bench):
 *   1. Bme280_Compensate_*  — фіксована-точка з datasheet Bosch §8.2
 *      (int32 T → °C×100; int64 P → Pa Q24.8; int32 H → %RH Q22.10).
 *      Host-тест звіряє цілочисельний шлях проти НЕЗАЛЕЖНОЇ float-копії
 *      тієї ж формули (дві транскрипції datasheet мусять зійтися —
 *      некругова golden, test_bme280.c).
 *   2. Bme280_Vpd_Index     — SVP за FAO-56 (Tetens), VPD = SVP·(1−RH/100),
 *      квантизація 0.02 kPa/LSB. 0x00 ЗАРЕЗЕРВОВАНО = «немає BME280»;
 *      реальний замір сатурується до ≥1, щоб не зіткнутися з сентинелем.
 *   3. Bme280_Read_Calib / Bme280_Forced_Read — послідовність регістрів
 *      forced-mode через ops-шов Bme280_Ops (прецедент FlashKvOps /
 *      g_ota_flash_ops): host = фейк регістрів, MCU = HAL_I2C у main.c.
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
 * один раз при bring-up з регістрів 0x88..0xA1 / 0xE1..0xE7 (Bme280_Read_Calib). */
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
 * 0 = чисельна сингулярність (var1==0) — викликач трактує як «недійсно».
 * Знакові `<<` Bosch-коду тут і в H — множення на 2ⁿ: LHS буває від'ємним
 * (var1·P2 < 0 щойно T > 25 °C), а в C11 це UB. gcc визначає `<<` рівно як
 * це множення → на кремнії бітово те саме, але UBSan-смуга бачить. */
static inline uint32_t Bme280_Compensate_P(const Bme280_Calib *c, int32_t adc_P,
                                          int32_t t_fine)
{
    int64_t var1 = ((int64_t)t_fine) - 128000;
    int64_t var2 = var1 * var1 * (int64_t)c->dig_P6;
    var2 = var2 + var1 * (int64_t)c->dig_P5 * ((int64_t)1 << 17);
    var2 = var2 + (int64_t)c->dig_P4 * ((int64_t)1 << 35);
    var1 = ((var1 * var1 * (int64_t)c->dig_P3) >> 8) +
           var1 * (int64_t)c->dig_P2 * ((int64_t)1 << 12);
    var1 = (((((int64_t)1) << 47) + var1)) * ((int64_t)c->dig_P1) >> 33;
    if (var1 == 0) {
        return 0; /* уникаємо ділення на нуль */
    }
    int64_t p = 1048576 - adc_P;
    p = (((p << 31) - var2) * 3125) / var1;
    var1 = (((int64_t)c->dig_P9) * (p >> 13) * (p >> 13)) >> 25;
    var2 = (((int64_t)c->dig_P8) * p) >> 19;
    p = ((p + var1 + var2) >> 8) + (int64_t)c->dig_P7 * 16;
    return (uint32_t)p;
}

/* Вологість: сирий 16-біт adc_H + t_fine → %RH у Q22.10 ("47445" = 46.33 %RH). */
static inline uint32_t Bme280_Compensate_H(const Bme280_Calib *c, int32_t adc_H,
                                          int32_t t_fine)
{
    int32_t v = (t_fine - ((int32_t)76800));
    v = (((((adc_H << 14) - (int32_t)c->dig_H4 * 1048576 -
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

/* ── Транспорт forced-mode (ops-шов) ─────────────────────────────────────
 * Регістри й таймінги — datasheet BST-BME280-DS001 rev 1.24 (розділи нижче).
 * Контракт викликача (SENSE, вшивається разом із CCM-флипом):
 *   · після TPS22860 ON — ≥ t_startup 2 мс (§1.1 Table 1) + t_ON самого ключа;
 *     справжній settle міряє стенд;
 *   · код ≠ BME280_OK → у кадр іде сентинель 0x00 «немає BME280», НІКОЛИ
 *     попереднє чи «нейтральне» значення;
 *   · delay_ms у робочій фазі може бути HAL_Delay; у STOP2 SysTick стоїть
 *     (firmware #8), тож енергоощадніша STOP2+LPTIM міняє лише реалізацію опса.
 * Soft-reset (0xE0) і config (0xF5) не чіпаємо: гейт дає POR на кожне
 * читання, а скид config = 0x00 = IIR off (Table 18/28) — рівно §3.5.1. */
#define BME280_OK            0
#define BME280_ERR_I2C     (-1) /* NACK / збій шини */
#define BME280_ERR_CHIP_ID (-2) /* id ≠ 0x60 — не той чіп */
#define BME280_ERR_TIMEOUT (-3) /* measuring / im_update не впали в бюджет */
#define BME280_ERR_NO_DATA (-4) /* у даних скид-патерн: конверсії не було */

#define BME280_REG_CALIB_TP  0x88u /* 0x88..0xA1: T1..P9, 0xA0 резерв, H1 (Table 16) */
#define BME280_REG_ID        0xD0u
#define BME280_REG_CALIB_H   0xE1u /* 0xE1..0xE7: H2..H6 */
#define BME280_REG_CTRL_HUM  0xF2u
#define BME280_REG_STATUS    0xF3u
#define BME280_REG_CTRL_MEAS 0xF4u
#define BME280_REG_DATA      0xF7u /* 0xF7..0xFE: press[3] temp[3] hum[2] (§5.3) */

#define BME280_CHIP_ID          0x60u /* §5.4.1 */
#define BME280_STATUS_MEASURING 0x08u /* §5.4.4 Table 21, біт 3 */
#define BME280_STATUS_IM_UPDATE 0x01u /* біт 0 */

/* Профіль §3.5.1 «Weather monitoring»: forced, ×1/×1/×1, IIR off.
 * osrs 001 = ×1 (Tables 20/23/24), mode 01 = forced (Table 25). */
#define BME280_CTRL_HUM_X1         0x01u
#define BME280_CTRL_MEAS_FORCED_X1 ((0x1u << 5) | (0x1u << 2) | 0x1u) /* 0x25 */

/* §9.1: t_measure,max = 1.25 + 2.3·N_T + (2.3·N_P + 0.575) + (2.3·N_H + 0.575) мс;
 * ×1/×1/×1 → 9.3 → чекаємо 10. Понад це — ще одна t_measure дожидання: max-
 * таймінги стейт-машини §1 характеризовано лише на 0…+65 °C, а ліс мерзне. */
#define BME280_T_MEASURE_MAX_US (1250u + 2300u + (2300u + 575u) + (2300u + 575u))
#define BME280_T_MEASURE_MAX_MS ((BME280_T_MEASURE_MAX_US + 999u) / 1000u)
#define BME280_POLL_BUDGET_MS   BME280_T_MEASURE_MAX_MS

/* 1 = ACK, 0 = збій шини (як FlashKvOps). read — burst з авто-інкрементом
 * адреси (§6.2.2); write — один регістр (§6.2.1). */
typedef struct {
    int  (*read)(void *io, uint8_t reg, uint8_t *buf, uint16_t len);
    int  (*write)(void *io, uint8_t reg, uint8_t val);
    void (*delay_ms)(void *io, uint32_t ms);
} Bme280_Ops;

/* Сирі відліки АЦП — входи Bme280_Compensate_*: T/P 20 біт, H 16 біт (§4). */
typedef struct {
    int32_t adc_T, adc_P, adc_H;
} Bme280_Raw;

static inline int Bme280_Check_Id(const Bme280_Ops *ops, void *io)
{
    uint8_t id;
    if (!ops->read(io, BME280_REG_ID, &id, 1)) {
        return BME280_ERR_I2C;
    }
    /* 0x58 = BMP280 (§5.2 Table 17): pin- і регістро-сумісний, але вологості
     * НЕ має, а дешеві breakout'и продають його як BME280 — без цієї
     * перевірки VPD рахувався б із вигаданої RH. */
    return id == BME280_CHIP_ID ? BME280_OK : BME280_ERR_CHIP_ID;
}

/* Чекає, доки біти `mask` у status не впадуть — обмежено бюджетом, не вічно. */
static inline int Bme280_Wait_Status_Clear(const Bme280_Ops *ops, void *io,
                                           uint8_t mask)
{
    for (uint32_t waited = 0;; waited++) {
        uint8_t st;
        if (!ops->read(io, BME280_REG_STATUS, &st, 1)) {
            return BME280_ERR_I2C;
        }
        if ((st & mask) == 0u) {
            return BME280_OK;
        }
        if (waited >= BME280_POLL_BUDGET_MS) {
            return BME280_ERR_TIMEOUT;
        }
        ops->delay_ms(io, 1u);
    }
}

static inline uint16_t Bme280_Le16(const uint8_t *p)
{
    return (uint16_t)(p[0] | (p[1] << 8)); /* [7:0] / [15:8] — Table 16 */
}

/* Калібровка NVM (§4.2.2 Table 16). NVM незмінна → читати раз при bring-up,
 * кеш у RAM переживає будь-які цикли гейта. */
static inline int Bme280_Read_Calib(const Bme280_Ops *ops, void *io, Bme280_Calib *c)
{
    uint8_t a[26], b[7]; /* 0x88..0xA1, 0xE1..0xE7 */
    int rc = Bme280_Check_Id(ops, io);
    if (rc != BME280_OK) {
        return rc;
    }
    /* im_update = NVM ще копіюється в image-регістри (Table 21): калібровка
     * посеред копії — сміття. Часу копії датащит не дає — бюджет позичено
     * в measuring (стеля, не специфікація). */
    rc = Bme280_Wait_Status_Clear(ops, io, BME280_STATUS_IM_UPDATE);
    if (rc != BME280_OK) {
        return rc;
    }
    if (!ops->read(io, BME280_REG_CALIB_TP, a, sizeof a) ||
        !ops->read(io, BME280_REG_CALIB_H, b, sizeof b)) {
        return BME280_ERR_I2C;
    }
    c->dig_T1 = Bme280_Le16(&a[0]);
    c->dig_T2 = (int16_t)Bme280_Le16(&a[2]);
    c->dig_T3 = (int16_t)Bme280_Le16(&a[4]);
    c->dig_P1 = Bme280_Le16(&a[6]);
    c->dig_P2 = (int16_t)Bme280_Le16(&a[8]);
    c->dig_P3 = (int16_t)Bme280_Le16(&a[10]);
    c->dig_P4 = (int16_t)Bme280_Le16(&a[12]);
    c->dig_P5 = (int16_t)Bme280_Le16(&a[14]);
    c->dig_P6 = (int16_t)Bme280_Le16(&a[16]);
    c->dig_P7 = (int16_t)Bme280_Le16(&a[18]);
    c->dig_P8 = (int16_t)Bme280_Le16(&a[20]);
    c->dig_P9 = (int16_t)Bme280_Le16(&a[22]);
    c->dig_H1 = a[25]; /* a[24] = 0xA0 — поза Table 16 */
    c->dig_H2 = (int16_t)Bme280_Le16(&b[0]);
    c->dig_H3 = b[2];
    /* H4/H5 — знакові 12-бітні поля, що ДІЛЯТЬ 0xE5 (Table 16):
     *   H4 = 0xE4[11:4] | 0xE5[3:0],  H5 = 0xE6[11:4] | 0xE5[7:4].
     * Знак несе старший байт: (int8_t)·16 = знакорозширення 12 біт. */
    c->dig_H4 = (int16_t)((int8_t)b[3] * 16 + (b[4] & 0x0F));
    c->dig_H5 = (int16_t)((int8_t)b[5] * 16 + (b[4] >> 4));
    c->dig_H6 = (int8_t)b[6];
    return BME280_OK;
}

/* Один forced-замір (§3.3.3). Порядок ctrl_hum → ctrl_meas НЕСУЧИЙ:
 * ctrl_hum набуває чинності лише записом ctrl_meas (§5.4.3), тож навпаки =
 * вологість «skipped». Дані — одним burst'ом (§4: байти різних замірів не
 * змішаються). */
static inline int Bme280_Forced_Read(const Bme280_Ops *ops, void *io, Bme280_Raw *raw)
{
    uint8_t d[8];
    int rc = Bme280_Check_Id(ops, io);
    if (rc != BME280_OK) {
        return rc;
    }
    if (!ops->write(io, BME280_REG_CTRL_HUM, BME280_CTRL_HUM_X1) ||
        !ops->write(io, BME280_REG_CTRL_MEAS, BME280_CTRL_MEAS_FORCED_X1)) {
        return BME280_ERR_I2C;
    }
    ops->delay_ms(io, BME280_T_MEASURE_MAX_MS);
    rc = Bme280_Wait_Status_Clear(ops, io, BME280_STATUS_MEASURING);
    if (rc != BME280_OK) {
        return rc;
    }
    if (!ops->read(io, BME280_REG_DATA, d, sizeof d)) {
        return BME280_ERR_I2C;
    }
    /* msb[19:12] lsb[11:4] xlsb[7:4]→[3:0] (§5.4.7–5.4.9) */
    int32_t p = ((int32_t)d[0] << 12) | ((int32_t)d[1] << 4) | (d[2] >> 4);
    int32_t t = ((int32_t)d[3] << 12) | ((int32_t)d[4] << 4) | (d[5] >> 4);
    int32_t h = ((int32_t)d[6] << 8) | d[7];
    /* Скид-патерн (Table 18; він же «skipped», Tables 20/23/24) декодується в
     * правдоподібну кімнатну температуру — це відсутність заміру, не замір.
     * Ціна: справжній відлік, що влучив рівно в патерн, теж відкидається
     * (один крок АЦП на канал → один цикл сентинеля). */
    if (p == 0x80000 || t == 0x80000 || h == 0x8000) {
        return BME280_ERR_NO_DATA;
    }
    raw->adc_P = p;
    raw->adc_T = t;
    raw->adc_H = h;
    return BME280_OK;
}

#endif /* SILKEN_BME280_H */
