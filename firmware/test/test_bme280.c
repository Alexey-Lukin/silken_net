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
 * Build: make -C firmware/test bme280
 */
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
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

    printf("\n════════════════════════════════════════════════════════════════════\n");
    printf("Passed: %d, Failed: %d\n", tests_passed, tests_failed);
    return tests_failed == 0 ? 0 : 1;
}
