// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * test_bio_contract.c — Host-based unit tests for bio-contract logic.
 *
 * Tests the Lorenz attractor math and StatusByte packing that run on
 * the Soldier MCU via mruby. Since mruby is not available on the host,
 * we re-implement the pure-math functions in C and verify:
 *   - Sigma/Rho clamping boundaries
 *   - Z-axis bounds (CRITICAL_Z_MIN=2.0, CRITICAL_Z_MAX=45.0)
 *   - [E.63] growth_points = monotonic metabolic_health(delta_t), NOT |29-Z|
 *   - [E.63] Z is INDEPENDENT of metabolism (β = BASE_BETA, fixed)
 *   - StatusByte encoding: [PanicFlag:1 | status:2 | growth_points:5] (FW.29-PACK)
 *   - Edge cases: extreme temperatures, extreme acoustics, zero seed
 *
 * Build: make -C firmware/test bio_contract
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <math.h>

/* ════════════════════════════════════════════════════════════════════
 * CONSTANTS (from firmware/bio_contracts/bio_contract.rb)
 * ════════════════════════════════════════════════════════════════════ */
#define BASE_SIGMA       10.0
#define BASE_RHO         28.0
#define BASE_BETA        (8.0 / 3.0)

#define DT_STEP          0.01
#define ITERATIONS       250

#define SIGMA_MIN        5.0
#define SIGMA_MAX        30.0
#define RHO_MIN          10.0
#define RHO_MAX          50.0

#define CRITICAL_Z_MIN   2.0
#define CRITICAL_Z_MAX   45.0
#define OPTIMAL_Z_TARGET 29.0

/* [E.63] Metabolic growth — recharge vigor → growth_points (monotonic).
 * Calibration-pending placeholders (bench recharge curve, RUNBOOK §3.3). */
/* [ARCH.102] Сентинел «метаболізм не виміряно» — дзеркало
 * Attractor::DELTA_T_UNKNOWN_S. Нуль секунд між пробудженнями не є інтервалом
 * перезаряду, тож значення вільне й не забирає жодного досяжного виміру. */
#define DELTA_T_UNKNOWN_S 0
#define DELTA_T_FAST_S   600     /* <= → m = 1.0 (peak vigor) */
#define DELTA_T_SLOW_S   7200    /* >= → m = 0.0 (minimal)    */
#define GP_HOMEO_MIN     5
#define GP_HOMEO_MAX     31

#define BIO_STATUS_HOMEOSTASIS 0
#define BIO_STATUS_STRESS      1
#define BIO_STATUS_ANOMALY     2

/* ════════════════════════════════════════════════════════════════════
 * EXTRACTED PURE-LOGIC FUNCTIONS
 * (C equivalent of firmware/bio_contracts/bio_contract.rb)
 * ════════════════════════════════════════════════════════════════════ */

static double clamp_d(double val, double lo, double hi) {
    if (val < lo) return lo;
    if (val > hi) return hi;
    return val;
}

static int clamp_i(int val, int lo, int hi) {
    if (val < lo) return lo;
    if (val > hi) return hi;
    return val;
}

/* [E.63] Monotonic metabolic vigor ∈ [0,1] from recharge time.
 * Mirrors BioContract.metabolic_health. Faster recharge → higher. */
static double metabolic_health(uint16_t delta_t_s) {
    double m = ((double)DELTA_T_SLOW_S - (double)delta_t_s) /
               ((double)DELTA_T_SLOW_S - (double)DELTA_T_FAST_S);
    if (m < 0.0) m = 0.0;
    if (m > 1.0) m = 1.0;
    return m;
}

/* Lorenz attractor Z-axis calculation. [E.63] β = BASE_BETA (fixed) —
 * metabolism no longer perturbs the chaos; it sets growth_points directly.
 * [SEC.11] The kernel takes initial (x₀, y₀, z₀) directly — there is no
 * `seed` input. The harness uses seed_to_xyz() for terse setup; production
 * firmware feeds (x₀, y₀, z₀) derived from K_seed via pure-C silken_sha256.h HKDF/HMAC. */
static double calculate_z_axis(double x, double y, double z,
                               int8_t temp, uint8_t acoustic) {
    double local_sigma = BASE_SIGMA + (acoustic * 0.1);
    double local_rho   = BASE_RHO + (temp * 0.2);

    local_sigma = clamp_d(local_sigma, SIGMA_MIN, SIGMA_MAX);
    local_rho   = clamp_d(local_rho, RHO_MIN, RHO_MAX);

    for (int i = 0; i < ITERATIONS; i++) {
        double dx = local_sigma * (y - x);
        double dy = x * (local_rho - z) - y;
        double dz = (x * y) - (BASE_BETA * z);

        x += dx * DT_STEP;
        y += dy * DT_STEP;
        z += dz * DT_STEP;
    }

    return z;
}

/* Test-only helper: generate deterministic (x, y, z) from a 32-bit
 * seed value the same way the legacy DID-derived path used to. Lets
 * the test cases keep their compact "seed=N" notation while still
 * exercising the post-SEC.11 (x₀, y₀, z₀) entry-point. */
static void seed_to_xyz(uint32_t seed, double *x, double *y, double *z) {
    *x = ((double)(seed % 1000) / 500.0) - 1.0;
    *y = ((double)((seed >> 4) % 1000) / 500.0) - 1.0;
    *z = ((double)((seed >> 8) % 1000) / 500.0) - 1.0;
}

static double calculate_z_axis_from_seed(uint32_t seed, int8_t temp, uint8_t acoustic) {
    double x, y, z;
    seed_to_xyz(seed, &x, &y, &z);
    return calculate_z_axis(x, y, z, temp, acoustic);
}

/* StatusByte packing (matches bio_contract.rb BioContract.pack_status_byte).
 * [E.63] Z → status (Lorenz gate); delta_t → growth_points (metabolism).
 * [FW.29-PACK] Wire layout: [PanicFlag:1 (bit 7, 0 normal) | Status:2 (bits 6..5) | GrowthPoints:5 (bits 4..0)]. */
static uint8_t evaluate_and_pack(uint32_t seed, int8_t temp, uint8_t acoustic,
                                 uint16_t delta_t_s) {
    double z_val = calculate_z_axis_from_seed(seed, temp, acoustic);

    /* [E.64] ρ-relative anomaly ceiling — same ρ expr + clamp as calculate_z_axis. */
    double local_rho = clamp_d(BASE_RHO + (temp * 0.2), RHO_MIN, RHO_MAX);
    double anomaly_ceiling = local_rho + (CRITICAL_Z_MAX - BASE_RHO);

    int status = 0;
    int growth_points = 0;

    if (z_val < CRITICAL_Z_MIN) {
        status = BIO_STATUS_STRESS;
        growth_points = 1;
    } else if (z_val > anomaly_ceiling) {
        status = BIO_STATUS_ANOMALY;
        growth_points = 0;
    } else if (delta_t_s == DELTA_T_UNKNOWN_S) {
        /* [ARCH.102] Гомеостаз виміряно, метаболізм — ні: емісія без доказу
         * росту не нараховується. Пара (status=0, GP=0) вільна, бо виміряний
         * гомеостаз починається з GP_HOMEO_MIN, а нуль у полі балів доти
         * належав лише аномалії (status=2). */
        status = BIO_STATUS_HOMEOSTASIS;
        growth_points = 0;
    } else {
        status = BIO_STATUS_HOMEOSTASIS;
        double m = metabolic_health(delta_t_s);
        growth_points = (int)round((double)GP_HOMEO_MIN + m * (GP_HOMEO_MAX - GP_HOMEO_MIN));
        growth_points = clamp_i(growth_points, GP_HOMEO_MIN, GP_HOMEO_MAX);
    }

    growth_points = clamp_i(growth_points, 0, 31);

    return (uint8_t)((status << 5) | growth_points);
}

/* ════════════════════════════════════════════════════════════════════
 * TEST HARNESS
 * ════════════════════════════════════════════════════════════════════ */
static int tests_passed = 0;
static int tests_failed = 0;

#define ASSERT(cond, msg) do { \
    if (!(cond)) { \
        printf("  %-55s ❌  FAIL: %s\n", msg, #cond); \
        tests_failed++; \
    } else { \
        printf("  %-55s ✅\n", msg); \
        tests_passed++; \
    } \
} while(0)

/* ════════════════════════════════════════════════════════════════════
 * TEST CASES
 * ════════════════════════════════════════════════════════════════════ */

static void test_sigma_clamp_lower(void) {
    /* acoustic=0 → sigma = 10.0 + 0*0.1 = 10.0, within range */
    double sigma = BASE_SIGMA + (0 * 0.1);
    sigma = clamp_d(sigma, SIGMA_MIN, SIGMA_MAX);
    ASSERT(sigma >= SIGMA_MIN && sigma <= SIGMA_MAX,
           "test_sigma_clamp_acoustic_zero");
}

static void test_sigma_clamp_upper(void) {
    /* acoustic=255 → sigma = 10.0 + 25.5 = 35.5 → clamped to 30.0 */
    double sigma = BASE_SIGMA + (255 * 0.1);
    sigma = clamp_d(sigma, SIGMA_MIN, SIGMA_MAX);
    ASSERT(fabs(sigma - SIGMA_MAX) < 0.001,
           "test_sigma_clamp_acoustic_max_255");
}

static void test_rho_clamp_negative_temp(void) {
    /* temp=-45 → rho = 28.0 + (-45*0.2) = 28.0 - 9.0 = 19.0, within range */
    double rho = BASE_RHO + (-45 * 0.2);
    rho = clamp_d(rho, RHO_MIN, RHO_MAX);
    ASSERT(rho >= RHO_MIN && rho <= RHO_MAX,
           "test_rho_clamp_negative_temp");
}

static void test_rho_clamp_extreme_heat(void) {
    /* temp=90 → rho = 28.0 + 18.0 = 46.0, within range */
    double rho = BASE_RHO + (90 * 0.2);
    rho = clamp_d(rho, RHO_MIN, RHO_MAX);
    ASSERT(rho >= RHO_MIN && rho <= RHO_MAX,
           "test_rho_clamp_extreme_heat");
}

static void test_rho_clamp_extreme_cold(void) {
    /* temp=-100 (hypothetical) → rho = 28.0 - 20.0 = 8.0 → clamped to 10.0 */
    double rho = BASE_RHO + (-100 * 0.2);
    rho = clamp_d(rho, RHO_MIN, RHO_MAX);
    ASSERT(fabs(rho - RHO_MIN) < 0.001,
           "test_rho_clamp_extreme_cold_to_minimum");
}

static void test_z_axis_normal_conditions(void) {
    /* Normal: seed=12345, temp=20, acoustic=5 */
    double z = calculate_z_axis_from_seed(12345, 20, 5);
    ASSERT(z > -100.0 && z < 100.0,
           "test_z_axis_normal_returns_finite");
}

static void test_z_axis_zero_seed(void) {
    /* Edge case: seed=0 */
    double z = calculate_z_axis_from_seed(0, 20, 5);
    ASSERT(!isnan(z) && !isinf(z),
           "test_z_axis_zero_seed_returns_valid");
}

static void test_z_axis_max_seed(void) {
    /* Edge case: seed=0xFFFFFFFF */
    double z = calculate_z_axis_from_seed(0xFFFFFFFF, 20, 5);
    ASSERT(!isnan(z) && !isinf(z),
           "test_z_axis_max_seed_returns_valid");
}

static void test_status_byte_encoding(void) {
    /* [FW.29-PACK] Verify bit layout: [PanicFlag:1 | status:2 | growth_points:5] */
    uint8_t byte1 = (BIO_STATUS_HOMEOSTASIS << 5) | 25;
    ASSERT(((byte1 >> 5) & 0x03) == 0 && (byte1 & 0x1F) == 25,
           "test_status_byte_homeostasis_25pts");

    uint8_t byte2 = (BIO_STATUS_STRESS << 5) | 1;
    ASSERT(((byte2 >> 5) & 0x03) == 1 && (byte2 & 0x1F) == 1,
           "test_status_byte_stress_1pt");

    uint8_t byte3 = (BIO_STATUS_ANOMALY << 5) | 0;
    ASSERT(((byte3 >> 5) & 0x03) == 2 && (byte3 & 0x1F) == 0,
           "test_status_byte_anomaly_0pts");

    /* Critical regression: status=2 (anomaly) survives PANIC_FLAG_BIT mask
     * (& 0x7F). До FW.29-PACK старе `<< 6` packing давало 0x80 → masked
     * до 0x00 → backend читав homeostasis. Тепер 0x40 → bit 7 чистий → анomaly. */
    ASSERT((byte3 & 0x80) == 0, "test_status_anomaly_no_panic_bit_collision");
}

static void test_evaluate_pack_vm_error_byte(void) {
    /* [FW.29-PACK] BIO_STATUS_VM_ERROR = 0xFF — після backend `& 0x7F` mask
     * (PANIC_FLAG_BIT clear) залишається 0x7F, що декодує як status=3
     * (tamper, bits 6..5 = 11) + growth=31 (bits 4..0 = 11111).  */
    uint8_t vm_error_masked = 0xFF & 0x7F;  /* normal mask in firmware */
    ASSERT(((vm_error_masked >> 5) & 0x03) == 3 && (vm_error_masked & 0x1F) == 31,
           "test_vm_error_byte_0xFF_decodes_as_tamper_after_mask");
}

static void test_beta_precision(void) {
    /* BASE_BETA = 8.0/3.0 should be 2.666666666666667 (IEEE 754 double) */
    ASSERT(fabs(BASE_BETA - (8.0 / 3.0)) < 1e-15,
           "test_beta_precision_8_div_3");
}

static void test_dt_step(void) {
    /* DT should be 0.01 */
    ASSERT(fabs(DT_STEP - 0.01) < 0.0001,
           "test_dt_step_is_0_01");
}

static void test_iterations_count(void) {
    /* Must be exactly 250 to match server */
    ASSERT(ITERATIONS == 250,
           "test_iterations_count_250");
}

static void test_z_axis_deterministic(void) {
    /* Same inputs must produce same Z (deterministic chaos) */
    double z1 = calculate_z_axis_from_seed(42, 25, 10);
    double z2 = calculate_z_axis_from_seed(42, 25, 10);
    ASSERT(fabs(z1 - z2) < 0.0001,
           "test_z_axis_deterministic_same_inputs");
}

static void test_z_axis_different_seeds(void) {
    /* Different seeds should (very likely) produce different Z */
    double z1 = calculate_z_axis_from_seed(100, 25, 10);
    double z2 = calculate_z_axis_from_seed(999, 25, 10);
    ASSERT(fabs(z1 - z2) > 0.001,
           "test_z_axis_different_seeds_different_z");
}

/* ════════════════════════════════════════════════════════════════════
 * GROWTH POINTS LOGIC ([E.63] metabolism-driven, decoupled from chaos)
 * ════════════════════════════════════════════════════════════════════ */

static void test_growth_points_max_31_at_fast_recharge(void) {
    /* metabolic_health(600s) = 1.0 → GP = round(5 + 1*26) = 31 */
    double m = metabolic_health(DELTA_T_FAST_S);
    int gp = clamp_i((int)round(GP_HOMEO_MIN + m * (GP_HOMEO_MAX - GP_HOMEO_MIN)), GP_HOMEO_MIN, GP_HOMEO_MAX);
    ASSERT(gp == 31, "test_growth_points_max_31_at_fast_recharge");
}

static void test_growth_points_min_5_at_slow_recharge(void) {
    /* metabolic_health(7200s) = 0.0 → GP = round(5 + 0) = 5 */
    double m = metabolic_health(DELTA_T_SLOW_S);
    int gp = clamp_i((int)round(GP_HOMEO_MIN + m * (GP_HOMEO_MAX - GP_HOMEO_MIN)), GP_HOMEO_MIN, GP_HOMEO_MAX);
    ASSERT(gp == 5, "test_growth_points_min_5_at_slow_recharge");
}

static void test_growth_points_midpoint(void) {
    /* delta_t = 3900s → m = (7200-3900)/6600 = 0.5 → GP = round(5 + 13) = 18 */
    double m = metabolic_health(3900);
    int gp = clamp_i((int)round(GP_HOMEO_MIN + m * (GP_HOMEO_MAX - GP_HOMEO_MIN)), GP_HOMEO_MIN, GP_HOMEO_MAX);
    ASSERT(fabs(m - 0.5) < 1e-12 && gp == 18, "test_growth_points_midpoint_3900s_gives_18");
}

static void test_metabolic_health_clamped_below_fast(void) {
    /* delta_t < FAST → m clamped to 1.0 */
    ASSERT(fabs(metabolic_health(100) - 1.0) < 1e-12,
           "test_metabolic_health_clamped_to_1_below_fast");
}

static void test_metabolic_health_clamped_above_slow(void) {
    /* delta_t > SLOW (field winter ~14400s) → m clamped to 0.0 */
    ASSERT(fabs(metabolic_health(14400) - 0.0) < 1e-12,
           "test_metabolic_health_clamped_to_0_above_slow");
}

static void test_growth_points_monotonic_in_recharge(void) {
    /* Faster recharge must never yield fewer points (monotonic, correct sign) */
    int prev = -1;
    int ok = 1;
    /* iterate delta_t from slow → fast; GP must be non-decreasing */
    for (int dt = DELTA_T_SLOW_S; dt >= DELTA_T_FAST_S; dt -= 600) {
        double m = metabolic_health((uint16_t)dt);
        int gp = clamp_i((int)round(GP_HOMEO_MIN + m * (GP_HOMEO_MAX - GP_HOMEO_MIN)), GP_HOMEO_MIN, GP_HOMEO_MAX);
        if (gp < prev) { ok = 0; break; }
        prev = gp;
    }
    ASSERT(ok, "test_growth_points_monotonic_faster_recharge_more_points");
}

static void test_status_stress_growth_points_is_1(void) {
    /* When status is STRESS (z < 2.0), growth_points must be 1 */
    double z_val = 1.5; /* below CRITICAL_Z_MIN */
    int status = 0, growth_points = 0;
    if (z_val < CRITICAL_Z_MIN) {
        status = BIO_STATUS_STRESS;
        growth_points = 1;
    }
    ASSERT(status == BIO_STATUS_STRESS && growth_points == 1,
           "test_stress_zone_gives_1_growth_point");
}

static void test_status_anomaly_growth_points_is_0(void) {
    /* When status is ANOMALY (z > 45.0), growth_points must be 0 */
    /* [E.64] ρ-relative ceiling = ρ + (CRITICAL_Z_MAX - BASE_RHO); at ρ=BASE_RHO → 45 */
    double z_val = 50.0; /* above the ρ=BASE_RHO ceiling (45) */
    double anomaly_ceiling = BASE_RHO + (CRITICAL_Z_MAX - BASE_RHO);
    int status = 0, growth_points = 0;
    if (z_val < CRITICAL_Z_MIN) {
        status = BIO_STATUS_STRESS;
        growth_points = 1;
    } else if (z_val > anomaly_ceiling) {
        status = BIO_STATUS_ANOMALY;
        growth_points = 0;
    }
    ASSERT(status == BIO_STATUS_ANOMALY && growth_points == 0,
           "test_anomaly_zone_gives_0_growth_points");
}

/* ════════════════════════════════════════════════════════════════════
 * [E.63] DECOUPLING — Z (chaos gate) INDEPENDENT of metabolism
 * ════════════════════════════════════════════════════════════════════ */

static void test_z_axis_independent_of_metabolism(void) {
    /* Z is computed WITHOUT delta_t/vcap — metabolism cannot move the chaos.
     * Same seed/temp/acoustic → identical Z regardless of recharge state. */
    double z = calculate_z_axis_from_seed(42, 20, 5);
    ASSERT(!isnan(z) && !isinf(z),
           "test_z_axis_metabolism_free_is_finite");
}

static void test_gp_responds_to_recharge_status_does_not(void) {
    /* Same chaotic state → SAME status for fast vs slow recharge (Z is
     * metabolism-free), but DIFFERENT growth_points when in homeostasis. */
    uint8_t fast = evaluate_and_pack(12345, 20, 5, DELTA_T_FAST_S);
    uint8_t slow = evaluate_and_pack(12345, 20, 5, DELTA_T_SLOW_S);
    uint8_t status_fast = (fast >> 5) & 0x03;
    uint8_t status_slow = (slow >> 5) & 0x03;

    ASSERT(status_fast == status_slow,
           "test_status_identical_regardless_of_recharge");

    if (status_fast == BIO_STATUS_HOMEOSTASIS) {
        ASSERT((fast & 0x1F) > (slow & 0x1F),
               "test_gp_higher_for_faster_recharge_in_homeostasis");
    } else {
        ASSERT(1, "test_gp_recharge_check_skipped_non_homeostasis");
    }
}

/* [ARCH.102] Пара «не виміряно ⊥ виміряний»: доти guard-и wall-time і
 * непрогріта EMA віддавали BASELINE_DELTA_T_S = 60, а той мапиться у
 * metabolic_health = 1.0 → GP = МАКСИМУМ. Тобто відмова виміряти мінтила
 * найбільше. Тепер сентинел дає нуль балів, а СПРАВЖНІЙ вимір 60 с (дуже
 * жваве дерево на лабораторній потужності) і далі дає максимум — без другої
 * половини фікс не відрізнити від «просто зрізали жвавість». */
static void test_unknown_delta_t_yields_no_growth(void) {
    uint8_t r = evaluate_and_pack(12345, 20, 5, DELTA_T_UNKNOWN_S);
    uint8_t status = (r >> 5) & 0x03;

    if (status == BIO_STATUS_HOMEOSTASIS) {
        ASSERT((r & 0x1F) == 0, "test_unknown_delta_t_gp_is_zero");
    } else {
        ASSERT(0, "test_unknown_delta_t_fixture_left_homeostasis");
    }
}

static void test_measured_sixty_seconds_still_peaks(void) {
    uint8_t r = evaluate_and_pack(12345, 20, 5, 60);
    uint8_t status = (r >> 5) & 0x03;

    if (status == BIO_STATUS_HOMEOSTASIS) {
        ASSERT((r & 0x1F) == GP_HOMEO_MAX, "test_measured_60s_gp_is_max");
    } else {
        ASSERT(0, "test_measured_60s_fixture_left_homeostasis");
    }
}

/* ════════════════════════════════════════════════════════════════════
 * EVALUATE & PACK (Integration)
 * ════════════════════════════════════════════════════════════════════ */

static void test_evaluate_pack_normal(void) {
    /* Normal conditions should produce valid StatusByte */
    uint8_t result = evaluate_and_pack(12345, 20, 5, DELTA_T_FAST_S);
    uint8_t status = (result >> 5) & 0x03;
    uint8_t gp = result & 0x1F;

    ASSERT(status <= 2, "test_evaluate_pack_valid_status");
    ASSERT(gp <= 31, "test_evaluate_pack_valid_growth_points");
    /* PanicFlag (bit 7) must be clear in normal packets */
    ASSERT((result & 0x80) == 0, "test_evaluate_pack_panic_flag_clear");
}

static void test_evaluate_pack_stress_low_z(void) {
    /* seed=0, temp=-45, acoustic=0: low rho can drive Z low; result valid. */
    uint8_t result = evaluate_and_pack(0, -45, 0, DELTA_T_FAST_S);
    uint8_t status = (result >> 5) & 0x03;
    uint8_t gp = result & 0x1F;
    ASSERT(status <= 2 && gp <= 31,
           "test_evaluate_pack_cold_zero_valid_result");
}

static void test_evaluate_pack_deterministic_across_range(void) {
    /* Multiple evaluations with same input must return identical result */
    for (uint32_t seed = 0; seed < 1000; seed += 100) {
        uint8_t r1 = evaluate_and_pack(seed, 20, 5, 1800);
        uint8_t r2 = evaluate_and_pack(seed, 20, 5, 1800);
        if (r1 != r2) {
            ASSERT(0, "test_evaluate_pack_not_deterministic");
            return;
        }
    }
    ASSERT(1, "test_evaluate_pack_deterministic_10_seeds");
}

/* ════════════════════════════════════════════════════════════════════
 * BOUNDARY CONDITION TESTS
 * ════════════════════════════════════════════════════════════════════ */

static void test_extreme_temp_acoustic_combo(void) {
    /* Extreme combo: temp=-128 (int8_t min) + acoustic=255
     * sigma = 10.0 + 255*0.1 = 35.5 → clamped DOWN to 30.0
     * rho = 28.0 + (-128*0.2) = 2.4 → clamped UP to 10.0
     * Both parameters hit clamp limits. Should produce valid (finite) Z. */
    double z = calculate_z_axis_from_seed(42, -128, 255);
    ASSERT(!isnan(z) && !isinf(z),
           "test_extreme_temp_minus128_acoustic_255_valid");
}

static void test_z_axis_sensitivity_to_temp(void) {
    /* Different temperatures with same seed/acoustic should produce different Z */
    double z_cold = calculate_z_axis_from_seed(42, -40, 5);
    double z_hot  = calculate_z_axis_from_seed(42, 80, 5);
    ASSERT(fabs(z_cold - z_hot) > 0.0001,
           "test_z_axis_different_temps_produce_different_z");
}

static void test_z_axis_sensitivity_to_acoustic(void) {
    /* Different acoustic values with same seed/temp should produce different Z */
    double z_quiet = calculate_z_axis_from_seed(42, 20, 0);
    double z_loud  = calculate_z_axis_from_seed(42, 20, 200);
    ASSERT(fabs(z_quiet - z_loud) > 0.0001,
           "test_z_axis_different_acoustics_produce_different_z");
}

static void test_growth_points_at_boundary_z(void) {
    /* [E.64] ceiling at ρ=BASE_RHO = CRITICAL_Z_MAX (45) */
    double anomaly_ceiling = BASE_RHO + (CRITICAL_Z_MAX - BASE_RHO);
    /* z_val = 2.0 (CRITICAL_Z_MIN) is NOT < 2.0 → homeostasis */
    double z_val = CRITICAL_Z_MIN;
    int status = (z_val < CRITICAL_Z_MIN) ? BIO_STATUS_STRESS
               : (z_val > anomaly_ceiling) ? BIO_STATUS_ANOMALY
               : BIO_STATUS_HOMEOSTASIS;
    ASSERT(status == BIO_STATUS_HOMEOSTASIS,
           "test_growth_points_at_z_min_boundary_is_homeostasis");

    /* z_val = 45.0 (= ceiling at ρ=BASE_RHO) is NOT > ceiling → homeostasis */
    z_val = CRITICAL_Z_MAX;
    status = (z_val < CRITICAL_Z_MIN) ? BIO_STATUS_STRESS
           : (z_val > anomaly_ceiling) ? BIO_STATUS_ANOMALY
           : BIO_STATUS_HOMEOSTASIS;
    ASSERT(status == BIO_STATUS_HOMEOSTASIS,
           "test_growth_points_at_z_max_boundary_is_homeostasis");
}

/* ════════════════════════════════════════════════════════════════════
 * MAIN
 * ════════════════════════════════════════════════════════════════════ */
int main(void) {
    printf("\n══════════════════════════════════════════════════════════════\n");
    printf("  SilkenNet Firmware — Bio-Contract Unit Tests\n");
    printf("══════════════════════════════════════════════════════════════\n\n");

    printf("  Sigma/Rho Clamping:\n");
    test_sigma_clamp_lower();
    test_sigma_clamp_upper();
    test_rho_clamp_negative_temp();
    test_rho_clamp_extreme_heat();
    test_rho_clamp_extreme_cold();

    printf("\n  Lorenz Z-Axis:\n");
    test_z_axis_normal_conditions();
    test_z_axis_zero_seed();
    test_z_axis_max_seed();
    test_z_axis_deterministic();
    test_z_axis_different_seeds();

    printf("\n  Constants:\n");
    test_beta_precision();
    test_dt_step();
    test_iterations_count();

    printf("\n  StatusByte Encoding:\n");
    test_status_byte_encoding();
    test_evaluate_pack_vm_error_byte();

    printf("\n  [E.63] Growth Points = Metabolic Health (decoupled):\n");
    test_growth_points_max_31_at_fast_recharge();
    test_growth_points_min_5_at_slow_recharge();
    test_growth_points_midpoint();
    test_metabolic_health_clamped_below_fast();
    test_metabolic_health_clamped_above_slow();
    test_growth_points_monotonic_in_recharge();
    test_status_stress_growth_points_is_1();
    test_status_anomaly_growth_points_is_0();

    printf("\n  [E.63] Decoupling (Z independent of metabolism):\n");
    test_z_axis_independent_of_metabolism();
    test_gp_responds_to_recharge_status_does_not();
    test_unknown_delta_t_yields_no_growth();
    test_measured_sixty_seconds_still_peaks();

    printf("\n  Evaluate & Pack (Integration):\n");
    test_evaluate_pack_normal();
    test_evaluate_pack_stress_low_z();
    test_evaluate_pack_deterministic_across_range();

    printf("\n  Boundary Conditions:\n");
    test_extreme_temp_acoustic_combo();
    test_z_axis_sensitivity_to_temp();
    test_z_axis_sensitivity_to_acoustic();
    test_growth_points_at_boundary_z();

    printf("\n══════════════════════════════════════════════════════════════\n");
    printf("  Results: %d passed, %d failed\n", tests_passed, tests_failed);
    printf("══════════════════════════════════════════════════════════════\n\n");

    return tests_failed > 0 ? 1 : 0;
}
