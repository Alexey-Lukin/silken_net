// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * test_bme280.c — [HW.32] компенсація BME280 + квантизація VPD (host).
 *
 * Некругова golden: цілочисельний шлях datasheet Bosch §8.2 (bme280.h)
 * звіряється проти НЕЗАЛЕЖНОЇ float-копії тієї ж формули (datasheet §8.1),
 * відтвореної ТУТ. Дві окремі транскрипції datasheet мусять зійтися —
 * друкарська помилка в одній не збіжиться з іншою (на відміну від pinning
 * власного виходу як «еталона»). Допуски поглинають фіксовану-точку, але
 * лишаються тісними, щоб зловити транскрипційний баг.
 *
 * VPD — hand-anchored вектори FAO-56 (Tetens) + інваріанти (сентинель 0x00,
 * сатурація стелі, монотонність по RH).
 *
 * Транспорт forced-mode — фейк регістрів із семантикою датащита (дані лише
 * по завершенні конверсії, ctrl_hum застібається записом ctrl_meas, POR-скид
 * у регістрах даних); наскрізний golden — розібраний приклад Bosch.
 *
 * Build: make -C firmware/test bme280
 */
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <math.h>

#include "../common/bme280.h"

static int tests_passed = 0;
static int tests_failed = 0;

static int last_failed = 0;
#define RUN(name) do { \
    last_failed = 0; \
    printf("  %-58s", #name); \
    name(); \
    if (!last_failed) { printf(" ✅\n"); tests_passed++; } \
} while(0)

#define FAILF(fmt, ...) do { \
    printf(" ❌ FAIL (line %d: " fmt ")\n", __LINE__, __VA_ARGS__); \
    tests_failed++; last_failed = 1; return; \
} while(0)

#define ASSERT_NEAR(got, exp, tol) do { \
    double _g = (double)(got), _e = (double)(exp); \
    if (fabs(_g - _e) > (tol)) FAILF("got %.4f, expected %.4f (tol %.4f)", _g, _e, (double)(tol)); \
} while(0)

#define ASSERT_EQ(a, b) do { \
    long long _a = (long long)(a), _b = (long long)(b); \
    if (_a != _b) FAILF("got %lld, expected %lld", _a, _b); \
} while(0)

/* ── Незалежна float-референс-компенсація (datasheet Bosch §8.1) ───────────
 * НЕ для прошивки (flash-кошт + soft-float на WLE5 без FPU) — лише golden. */
static double Ref_T(const Bme280_Calib *c, int32_t adc_T, int32_t *t_fine_out)
{
    double var1 = (((double)adc_T) / 16384.0 - ((double)c->dig_T1) / 1024.0) *
                  ((double)c->dig_T2);
    double var2 = ((((double)adc_T) / 131072.0 - ((double)c->dig_T1) / 8192.0) *
                   (((double)adc_T) / 131072.0 - ((double)c->dig_T1) / 8192.0)) *
                  ((double)c->dig_T3);
    *t_fine_out = (int32_t)(var1 + var2);
    return (var1 + var2) / 5120.0;
}

static double Ref_P(const Bme280_Calib *c, int32_t adc_P, int32_t t_fine)
{
    double var1 = ((double)t_fine / 2.0) - 64000.0;
    double var2 = var1 * var1 * ((double)c->dig_P6) / 32768.0;
    var2 = var2 + var1 * ((double)c->dig_P5) * 2.0;
    var2 = (var2 / 4.0) + (((double)c->dig_P4) * 65536.0);
    var1 = (((double)c->dig_P3) * var1 * var1 / 524288.0 +
            ((double)c->dig_P2) * var1) / 524288.0;
    var1 = (1.0 + var1 / 32768.0) * ((double)c->dig_P1);
    if (var1 == 0.0) {
        return 0.0;
    }
    double p = 1048576.0 - (double)adc_P;
    p = (p - (var2 / 4096.0)) * 6250.0 / var1;
    var1 = ((double)c->dig_P9) * p * p / 2147483648.0;
    var2 = p * ((double)c->dig_P8) / 32768.0;
    return p + (var1 + var2 + ((double)c->dig_P7)) / 16.0;
}

static double Ref_H(const Bme280_Calib *c, int32_t adc_H, int32_t t_fine)
{
    double var_H = (((double)t_fine) - 76800.0);
    var_H = (adc_H - (((double)c->dig_H4) * 64.0 + ((double)c->dig_H5) / 16384.0 * var_H)) *
            (((double)c->dig_H2) / 65536.0 *
             (1.0 + ((double)c->dig_H6) / 67108864.0 * var_H *
              (1.0 + ((double)c->dig_H3) / 67108864.0 * var_H)));
    var_H = var_H * (1.0 - ((double)c->dig_H1) * var_H / 524288.0);
    if (var_H > 100.0) {
        var_H = 100.0;
    } else if (var_H < 0.0) {
        var_H = 0.0;
    }
    return var_H;
}

/* Реалістичний калібрувальний дамп (типові величини NVM BME280). */
static const Bme280_Calib CALIB = {
    .dig_T1 = 28485, .dig_T2 = 26735, .dig_T3 = 50,
    .dig_P1 = 37190, .dig_P2 = -10497, .dig_P3 = 3024, .dig_P4 = 6630,
    .dig_P5 = -141, .dig_P6 = -7, .dig_P7 = 15500, .dig_P8 = -14600, .dig_P9 = 6000,
    .dig_H1 = 75, .dig_H2 = 361, .dig_H3 = 0, .dig_H4 = 339, .dig_H5 = 0, .dig_H6 = 30,
};

/* Свіп сирих 20-біт/16-біт значень навколо типового forced-mode заміру. */
static const int32_t ADC_T[] = { 415000, 480000, 519888, 540000, 600000 };
static const int32_t ADC_P[] = { 300000, 326816, 350000, 415000, 500000 };
static const int32_t ADC_H[] = { 12000, 25000, 30702, 40000, 55000 };
#define NSWEEP (sizeof(ADC_T) / sizeof(ADC_T[0]))

static void test_temperature_int_matches_float(void)
{
    for (unsigned i = 0; i < NSWEEP; i++) {
        int32_t tf_i, tf_f;
        int32_t ti = Bme280_Compensate_T(&CALIB, ADC_T[i], &tf_i);
        double tf_ref = Ref_T(&CALIB, ADC_T[i], &tf_f);
        ASSERT_NEAR((double)ti / 100.0, tf_ref, 0.02); /* ≤0.02 °C квантування */
    }
}

static void test_pressure_int_matches_float(void)
{
    for (unsigned i = 0; i < NSWEEP; i++) {
        int32_t tf;
        (void)Bme280_Compensate_T(&CALIB, ADC_T[2], &tf);
        uint32_t pi = Bme280_Compensate_P(&CALIB, ADC_P[i], tf);
        double pf = Ref_P(&CALIB, ADC_P[i], tf);
        ASSERT_NEAR((double)pi / 256.0, pf, 1.0); /* ≤1 Pa */
    }
}

static void test_humidity_int_matches_float(void)
{
    for (unsigned i = 0; i < NSWEEP; i++) {
        int32_t tf;
        (void)Bme280_Compensate_T(&CALIB, ADC_T[2], &tf);
        uint32_t hi = Bme280_Compensate_H(&CALIB, ADC_H[i], tf);
        double hf = Ref_H(&CALIB, ADC_H[i], tf);
        ASSERT_NEAR((double)hi / 1024.0, hf, 0.2); /* ≤0.2 %RH */
    }
}

static void test_pressure_in_physical_range(void)
{
    /* Санітарна межа: компенсований тиск у реалістичному діапазоні (300..1100 hPa). */
    int32_t tf;
    (void)Bme280_Compensate_T(&CALIB, ADC_T[2], &tf);
    double hpa = (double)Bme280_Compensate_P(&CALIB, ADC_P[1], tf) / 256.0 / 100.0;
    if (hpa < 300.0 || hpa > 1100.0) FAILF("pressure %.1f hPa out of [300,1100]", hpa);
}

static void test_pressure_zero_divisor_guard(void)
{
    /* dig_P1 = 0 ⇒ var1 == 0 у datasheet-шляху §8.2 → guard від ділення на
     * нуль повертає 0 = «недійсний тиск» (викликач так і трактує). Порожня
     * NVM / нечитаний калібрувальний блок дає саме такий нуль. */
    Bme280_Calib c = CALIB;
    c.dig_P1 = 0;
    int32_t tf;
    (void)Bme280_Compensate_T(&c, ADC_T[2], &tf);
    ASSERT_EQ(Bme280_Compensate_P(&c, ADC_P[1], tf), 0u);
}

/* ── VPD: hand-anchored FAO-56 (Tetens) ───────────────────────────────────
 * e_s = 0.6108·exp(17.27·T/(T+237.3)); VPD = e_s·(1−RH/100); idx = round(VPD/0.02). */
static void test_vpd_hand_anchored(void)
{
    /* T=25, RH=50 → VPD≈1.584 kPa → 79 */
    ASSERT_EQ(Bme280_Vpd_Index(25.0, 50.0), 79);
    /* T=30, RH=40 → VPD≈2.546 kPa → 127 */
    ASSERT_EQ(Bme280_Vpd_Index(30.0, 40.0), 127);
    /* T=10, RH=80 → VPD≈0.246 kPa → 12 */
    ASSERT_EQ(Bme280_Vpd_Index(10.0, 80.0), 12);
}

static void test_vpd_saturated_air_floor(void)
{
    /* RH=100% → VPD=0, але сенсор присутній → ≥1 (0x00 = «немає сенсора»). */
    ASSERT_EQ(Bme280_Vpd_Index(25.0, 100.0), BME280_VPD_INDEX_MIN);
    ASSERT_EQ(Bme280_Vpd_Index(5.0, 100.0), BME280_VPD_INDEX_MIN);
}

static void test_vpd_saturates_ceiling(void)
{
    /* T=40, RH=20 → VPD≈5.90 kPa > 5.1 стеля → 255. */
    ASSERT_EQ(Bme280_Vpd_Index(40.0, 20.0), BME280_VPD_INDEX_MAX);
}

static void test_vpd_monotonic_in_rh(void)
{
    /* При фіксованій T нижча RH ⇒ більший дефіцит ⇒ більший (або рівний) index. */
    uint8_t prev = Bme280_Vpd_Index(25.0, 100.0);
    for (double rh = 90.0; rh >= 0.0; rh -= 10.0) {
        uint8_t cur = Bme280_Vpd_Index(25.0, rh);
        if (cur < prev) FAILF("non-monotone at RH=%.0f: %u < %u", rh, cur, prev);
        prev = cur;
    }
}

static void test_vpd_clamps_garbage_rh(void)
{
    /* RH поза [0,100] не повинна підривати формулу. */
    ASSERT_EQ(Bme280_Vpd_Index(25.0, 150.0), BME280_VPD_INDEX_MIN); /* → RH 100 */
    ASSERT_EQ(Bme280_Vpd_Index(25.0, -10.0), Bme280_Vpd_Index(25.0, 0.0));
}

static void test_vpd_from_compensated_bridge(void)
{
    /* Q-формати компенсації → той самий байт, що прямий double-виклик. */
    int32_t temp_centi = 2500;       /* 25.00 °C */
    uint32_t rh_q10 = 50u * 1024u;   /* 50.0 %RH */
    ASSERT_EQ(Bme280_Vpd_Index_From_Compensated(temp_centi, rh_q10),
              Bme280_Vpd_Index(25.0, 50.0));
}

/* ── Транспорт forced-mode: фейк BME280 на регістрах ──────────────────────
 * Golden-калібровка = розібраний приклад Bosch (BST-BMP280-DS001-11 rev 1.14,
 * §3.12, стор. 23): T/P-тракт BME280 з BMP280 ідентичний (BME280 §5.2).
 * Байти закодовано ВРУЧНУ з таблиці значень little-endian [7:0]/[15:8]
 * (BME280 Table 16) — незалежно від декодера. H-блоку приклад не має:
 * реалістичні H1..H6, у H4/H5 РІЗНІ нібли 0xE5, щоб переставлення ловилось. */
static const uint8_t CALIB_TP_IMG[26] = {
    0x70, 0x6B, /* T1 = 27504 */
    0x43, 0x67, /* T2 = 26435 */
    0x18, 0xFC, /* T3 = -1000 */
    0x7D, 0x8E, /* P1 = 36477 */
    0x43, 0xD6, /* P2 = -10685 */
    0xD0, 0x0B, /* P3 = 3024 */
    0x27, 0x0B, /* P4 = 2855 */
    0x8C, 0x00, /* P5 = 140 */
    0xF9, 0xFF, /* P6 = -7 */
    0x8C, 0x3C, /* P7 = 15500 */
    0xF8, 0xC6, /* P8 = -14600 */
    0x70, 0x17, /* P9 = 6000 */
    0xEE,       /* 0xA0 — резерв поза Table 16: отрута, мусить ігноруватись */
    0x4B,       /* H1 = 75 */
};
/* 0xE1..0xE7: H2 = 361, H3 = 0, H4 = 0x14<<4 | 0x1 = 321, H5 = 0x03<<4 | 0x2 = 50, H6 = 30. */
static const uint8_t CALIB_H_IMG[7] = { 0x69, 0x01, 0x00, 0x14, 0x21, 0x03, 0x1E };

/* 0xF7..0xFE: UP = 415148 = 0x655AC, UT = 519888 = 0x7EED0 (приклад Bosch;
 * колонку адрес UP/UT там переставлено відносно карти пам'яті — розкладка
 * з BME280 Table 18: 0xF7 press, 0xFA temp). UH = 0x73C5 (≈ 50 %RH). */
static const uint8_t DATA_IMG[8] = { 0x65, 0x5A, 0xC0, 0x7E, 0xED, 0x00, 0x73, 0xC5 };

typedef struct {
    uint8_t  reg[256];
    uint8_t  result[8];         /* «атмосфера», яку виміряє конверсія */
    uint8_t  pending[8];        /* що конверсія покладе в 0xF7..0xFE */
    int      has_pending;
    uint8_t  wr_reg[8], wr_val[8];
    int      n_wr;
    int      calls, fail_call;  /* fail_call-й I²C-виклик (з 1) → NACK; 0 = ніколи */
    uint32_t now_ms, busy_until_ms, delayed_ms, conv_ms, im_update_until_ms;
    int      stuck_measuring, ignore_forced;
} FakeBme;

static int fake_read(void *io, uint8_t reg, uint8_t *buf, uint16_t len)
{
    FakeBme *f = io;
    if (++f->calls == f->fail_call || (unsigned)reg + len > sizeof f->reg) {
        return 0;
    }
    int busy = f->stuck_measuring || f->now_ms < f->busy_until_ms;
    if (f->has_pending && !busy) { /* дані з'являються лише ПІСЛЯ конверсії */
        memcpy(&f->reg[BME280_REG_DATA], f->pending, sizeof f->pending);
        f->has_pending = 0;
    }
    if (reg == BME280_REG_STATUS && len == 1) {
        buf[0] = (uint8_t)((busy ? BME280_STATUS_MEASURING : 0u) |
                           (f->now_ms < f->im_update_until_ms ? BME280_STATUS_IM_UPDATE : 0u));
        return 1;
    }
    memcpy(buf, &f->reg[reg], len);
    return 1;
}

static int fake_write(void *io, uint8_t reg, uint8_t val)
{
    FakeBme *f = io;
    if (++f->calls == f->fail_call) {
        return 0;
    }
    if (f->n_wr < (int)sizeof f->wr_reg) {
        f->wr_reg[f->n_wr] = reg;
        f->wr_val[f->n_wr] = val;
        f->n_wr++;
    }
    f->reg[reg] = val;
    uint8_t mode = val & 0x03u;
    if (reg == BME280_REG_CTRL_MEAS && (mode == 1u || mode == 2u) && !f->ignore_forced) {
        memcpy(f->pending, f->result, sizeof f->pending);
        if ((f->reg[BME280_REG_CTRL_HUM] & 0x07u) == 0u) { /* §5.4.3: ctrl_hum діє з цього запису */
            f->pending[6] = 0x80; /* Table 20: humidity skipped → 0x8000 */
            f->pending[7] = 0x00;
        }
        f->has_pending = 1;
        f->busy_until_ms = f->now_ms + f->conv_ms;
    }
    return 1;
}

static void fake_delay(void *io, uint32_t ms)
{
    FakeBme *f = io;
    f->now_ms += ms;
    f->delayed_ms += ms;
}

static const Bme280_Ops FAKE_OPS = { fake_read, fake_write, fake_delay };

static void fake_init(FakeBme *f)
{
    memset(f, 0, sizeof *f);
    f->reg[BME280_REG_ID] = BME280_CHIP_ID;
    memcpy(&f->reg[BME280_REG_CALIB_TP], CALIB_TP_IMG, sizeof CALIB_TP_IMG);
    memcpy(&f->reg[BME280_REG_CALIB_H], CALIB_H_IMG, sizeof CALIB_H_IMG);
    f->reg[0xF7] = 0x80; /* POR-скид press/temp/hum_msb (Table 18) */
    f->reg[0xFA] = 0x80;
    f->reg[0xFD] = 0x80;
    memcpy(f->result, DATA_IMG, sizeof f->result);
    f->conv_ms = 9; /* < t_measure,max 9.3 мс */
}

static void test_forced_writes_ctrl_hum_before_ctrl_meas(void)
{
    FakeBme f;
    Bme280_Raw raw;
    fake_init(&f);
    ASSERT_EQ(Bme280_Forced_Read(&FAKE_OPS, &f, &raw), BME280_OK);
    ASSERT_EQ(f.n_wr, 2);
    ASSERT_EQ(f.wr_reg[0], BME280_REG_CTRL_HUM);
    ASSERT_EQ(f.wr_val[0], 0x01); /* osrs_h ×1 */
    ASSERT_EQ(f.wr_reg[1], BME280_REG_CTRL_MEAS);
    ASSERT_EQ(f.wr_val[1], 0x25); /* osrs_t ×1 | osrs_p ×1 | forced */
    ASSERT_EQ(f.delayed_ms, 10);  /* рівно t_measure,max (§9.1: 9.3 → 10) */
}

static void test_forced_burst_unpacks_20_20_16(void)
{
    FakeBme f;
    Bme280_Raw raw;
    fake_init(&f);
    ASSERT_EQ(Bme280_Forced_Read(&FAKE_OPS, &f, &raw), BME280_OK);
    ASSERT_EQ(raw.adc_P, 415148);
    ASSERT_EQ(raw.adc_T, 519888);
    ASSERT_EQ(raw.adc_H, 0x73C5);
}

static void test_calib_unpack_table16(void)
{
    FakeBme f;
    Bme280_Calib c;
    fake_init(&f);
    memset(&c, 0xA5, sizeof c);
    ASSERT_EQ(Bme280_Read_Calib(&FAKE_OPS, &f, &c), BME280_OK);
    ASSERT_EQ(c.dig_T1, 27504);
    ASSERT_EQ(c.dig_T2, 26435);
    ASSERT_EQ(c.dig_T3, -1000);
    ASSERT_EQ(c.dig_P1, 36477);
    ASSERT_EQ(c.dig_P2, -10685);
    ASSERT_EQ(c.dig_P3, 3024);
    ASSERT_EQ(c.dig_P4, 2855);
    ASSERT_EQ(c.dig_P5, 140);
    ASSERT_EQ(c.dig_P6, -7);
    ASSERT_EQ(c.dig_P7, 15500);
    ASSERT_EQ(c.dig_P8, -14600);
    ASSERT_EQ(c.dig_P9, 6000);
    ASSERT_EQ(c.dig_H1, 75);
    ASSERT_EQ(c.dig_H2, 361);
    ASSERT_EQ(c.dig_H3, 0);
    ASSERT_EQ(c.dig_H4, 321);
    ASSERT_EQ(c.dig_H5, 50);
    ASSERT_EQ(c.dig_H6, 30);
    ASSERT_EQ(f.n_wr, 0); /* калібровка — лише читання */
}

static void test_calib_h4_h5_sign_extension(void)
{
    /* Знакові 12 біт, вручну з Table 16: H4 = 0xE4 0xFB | 0xE5[3:0] 0x7 = 0xFB7
     * = −73; H5 = 0xE6 0xF3 | 0xE5[7:4] 0xA = 0xF3A = −198. */
    FakeBme f;
    Bme280_Calib c;
    fake_init(&f);
    f.reg[0xE4] = 0xFB;
    f.reg[0xE5] = 0xA7;
    f.reg[0xE6] = 0xF3;
    ASSERT_EQ(Bme280_Read_Calib(&FAKE_OPS, &f, &c), BME280_OK);
    ASSERT_EQ(c.dig_H4, -73);
    ASSERT_EQ(c.dig_H5, -198);
}

static void test_calib_waits_for_im_update(void)
{
    FakeBme f;
    Bme280_Calib c;
    fake_init(&f);
    f.im_update_until_ms = 3; /* NVM ще копіюється в image-регістри */
    ASSERT_EQ(Bme280_Read_Calib(&FAKE_OPS, &f, &c), BME280_OK);
    ASSERT_EQ(f.delayed_ms, 3);
    ASSERT_EQ(c.dig_T1, 27504);
}

static void test_slow_conversion_within_budget(void)
{
    /* Холодна конверсія довша за §9.1-max (max характеризовано лише 0…+65 °C) —
     * дожидаємо в межах бюджету. */
    FakeBme f;
    Bme280_Raw raw;
    fake_init(&f);
    f.conv_ms = 14;
    ASSERT_EQ(Bme280_Forced_Read(&FAKE_OPS, &f, &raw), BME280_OK);
    ASSERT_EQ(f.delayed_ms, 14);
    ASSERT_EQ(raw.adc_T, 519888);
}

static void test_stuck_status_times_out_bounded(void)
{
    FakeBme f;
    Bme280_Raw raw;
    Bme280_Calib c;
    fake_init(&f);
    f.stuck_measuring = 1;
    ASSERT_EQ(Bme280_Forced_Read(&FAKE_OPS, &f, &raw), BME280_ERR_TIMEOUT);
    ASSERT_EQ(f.delayed_ms, 2 * BME280_T_MEASURE_MAX_MS); /* max + бюджет, не вічність */

    fake_init(&f);
    f.im_update_until_ms = UINT32_MAX;
    ASSERT_EQ(Bme280_Read_Calib(&FAKE_OPS, &f, &c), BME280_ERR_TIMEOUT);
    ASSERT_EQ(f.delayed_ms, BME280_POLL_BUDGET_MS);
}

static void test_i2c_nack_at_every_step(void)
{
    /* Чистий прогін фіксує послідовність, далі NACK на КОЖНОМУ виклику по
     * черзі — жоден крок не ковтає збій шини. */
    FakeBme f;
    Bme280_Raw raw;
    Bme280_Calib c;
    fake_init(&f);
    ASSERT_EQ(Bme280_Forced_Read(&FAKE_OPS, &f, &raw), BME280_OK);
    ASSERT_EQ(f.calls, 5); /* id · ctrl_hum · ctrl_meas · status · burst */
    for (int k = 1; k <= 5; k++) {
        fake_init(&f);
        f.fail_call = k;
        int rc = Bme280_Forced_Read(&FAKE_OPS, &f, &raw);
        if (rc != BME280_ERR_I2C) FAILF("forced: NACK на виклику %d → rc %d", k, rc);
    }
    fake_init(&f);
    ASSERT_EQ(Bme280_Read_Calib(&FAKE_OPS, &f, &c), BME280_OK);
    ASSERT_EQ(f.calls, 4); /* id · status · 0x88 burst · 0xE1 burst */
    for (int k = 1; k <= 4; k++) {
        fake_init(&f);
        f.fail_call = k;
        int rc = Bme280_Read_Calib(&FAKE_OPS, &f, &c);
        if (rc != BME280_ERR_I2C) FAILF("calib: NACK на виклику %d → rc %d", k, rc);
    }
}

static void test_foreign_chip_id_touches_nothing(void)
{
    /* 0x58 = BMP280: pin-сумісний, вологості не має — жодного запису в чужий чіп. */
    FakeBme f;
    Bme280_Raw raw;
    Bme280_Calib c;
    fake_init(&f);
    f.reg[BME280_REG_ID] = 0x58;
    ASSERT_EQ(Bme280_Forced_Read(&FAKE_OPS, &f, &raw), BME280_ERR_CHIP_ID);
    ASSERT_EQ(Bme280_Read_Calib(&FAKE_OPS, &f, &c), BME280_ERR_CHIP_ID);
    ASSERT_EQ(f.n_wr, 0);
}

static void test_no_conversion_is_not_a_measurement(void)
{
    /* ctrl_meas «прийнято», а конверсії не було: у регістрах POR-скид. */
    FakeBme f;
    Bme280_Raw raw;
    Bme280_Calib c;
    int32_t tf;
    fake_init(&f);
    f.ignore_forced = 1;
    ASSERT_EQ(Bme280_Forced_Read(&FAKE_OPS, &f, &raw), BME280_ERR_NO_DATA);
    /* …а прочитаний як число, скид був би правдоподібною погодою. */
    ASSERT_EQ(Bme280_Read_Calib(&FAKE_OPS, &f, &c), BME280_OK);
    int32_t t = Bme280_Compensate_T(&c, 0x80000, &tf);
    if (t < 1500 || t > 3500) FAILF("скид-патерн дав %d (°C×100) — не «правдоподібний»?", t);
}

static void test_end_to_end_bosch_vector(void)
{
    /* Шина → калібровка → forced burst → компенсація. Очікування — приклад
     * Bosch (стор. 23): t_fine 128422 · T 2508 (°C×100) · int64 P 25767236
     * (1/256 Pa = 100653.27 Pa, «integer result may deviate slightly»).
     * H-вектора Bosch не публікує → незалежна float-транскрипція §8.1. */
    FakeBme f;
    Bme280_Calib c;
    Bme280_Raw raw;
    int32_t tf;
    fake_init(&f);
    ASSERT_EQ(Bme280_Read_Calib(&FAKE_OPS, &f, &c), BME280_OK);
    ASSERT_EQ(Bme280_Forced_Read(&FAKE_OPS, &f, &raw), BME280_OK);
    ASSERT_EQ(Bme280_Compensate_T(&c, raw.adc_T, &tf), 2508);
    ASSERT_EQ(tf, 128422);
    ASSERT_NEAR(Bme280_Compensate_P(&c, raw.adc_P, tf), 25767236, 256); /* ≤ 1 Pa */
    double rh = (double)Bme280_Compensate_H(&c, raw.adc_H, tf) / 1024.0;
    ASSERT_NEAR(rh, Ref_H(&c, raw.adc_H, tf), 0.2);
    if (rh < 40.0 || rh > 60.0) FAILF("RH %.2f %% поза очікуваним ≈50", rh);
}

int main(void)
{
    printf("════════════════════════════════════════════════════════════════════\n");
    printf("  [HW.32] BME280 компенсація + VPD-confounder — host golden\n");
    printf("════════════════════════════════════════════════════════════════════\n");

    printf("\n— Компенсація: int (datasheet §8.2) ↔ float-референс (§8.1) —\n");
    RUN(test_temperature_int_matches_float);
    RUN(test_pressure_int_matches_float);
    RUN(test_humidity_int_matches_float);
    RUN(test_pressure_in_physical_range);
    RUN(test_pressure_zero_divisor_guard);

    printf("\n— VPD: FAO-56 Tetens + інваріанти —\n");
    RUN(test_vpd_hand_anchored);
    RUN(test_vpd_saturated_air_floor);
    RUN(test_vpd_saturates_ceiling);
    RUN(test_vpd_monotonic_in_rh);
    RUN(test_vpd_clamps_garbage_rh);
    RUN(test_vpd_from_compensated_bridge);

    printf("\n— Транспорт forced-mode: фейк регістрів (DS001 rev 1.24) —\n");
    RUN(test_forced_writes_ctrl_hum_before_ctrl_meas);
    RUN(test_forced_burst_unpacks_20_20_16);
    RUN(test_calib_unpack_table16);
    RUN(test_calib_h4_h5_sign_extension);
    RUN(test_calib_waits_for_im_update);
    RUN(test_slow_conversion_within_budget);
    RUN(test_stuck_status_times_out_bounded);
    RUN(test_i2c_nack_at_every_step);
    RUN(test_foreign_chip_id_touches_nothing);
    RUN(test_no_conversion_is_not_a_measurement);
    RUN(test_end_to_end_bosch_vector);

    printf("\n════════════════════════════════════════════════════════════════════\n");
    printf("Passed: %d, Failed: %d\n", tests_passed, tests_failed);
    return tests_failed == 0 ? 0 : 1;
}
