/*
 * test_bio_contract.c — Host-based unit tests for bio-contract logic.
 *
 * Tests the Lorenz attractor math and StatusByte packing that run on
 * the Soldier MCU via mruby. Since mruby is not available on the host,
 * we re-implement the pure-math functions in C and verify:
 *   - Sigma/Rho clamping boundaries
 *   - Z-axis bounds (CRITICAL_Z_MIN=2.0, CRITICAL_Z_MAX=45.0)
 *   - Growth points calculation and 6-bit packing
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

/* [FW.5] β-perturbation constants — must mirror bio_contract.rb */
#define BETA_DELTA_T_COEFF  0.0001
#define BETA_VCAP_COEFF     0.001
#define BETA_MIN            2.0
#define BETA_MAX            4.0
#define BASELINE_DELTA_T_S  60
#define NOMINAL_VCAP_MV     3300

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

/* [FW.5] β perturbation helper — mirrors SilkenNet::Attractor.perturb_beta */
static double perturb_beta(uint16_t delta_t_s, uint16_t vcap_mv) {
    double dt_improvement = (double)BASELINE_DELTA_T_S - (double)delta_t_s;
    if (dt_improvement < 0.0) dt_improvement = 0.0;
    double vcap_centered = (double)vcap_mv - (double)NOMINAL_VCAP_MV;

    double beta = (8.0 / 3.0) +
                  (dt_improvement * BETA_DELTA_T_COEFF) +
                  (vcap_centered  * BETA_VCAP_COEFF);
    return clamp_d(beta, BETA_MIN, BETA_MAX);
}

/* Lorenz attractor Z-axis calculation.
 * [SEC.11] After the seed-provenance hard cutover, the kernel takes
 * initial (x₀, y₀, z₀) directly — there is no `seed` input. The test
 * harness uses a small `seed_to_xyz()` helper to keep the per-test
 * setup terse; production firmware feeds (x₀, y₀, z₀) derived from
 * K_seed via mbedTLS HKDF/HMAC. */
static double calculate_z_axis(double x, double y, double z,
                               int8_t temp, uint8_t acoustic,
                               uint16_t delta_t_s, uint16_t vcap_mv) {
    double local_sigma = BASE_SIGMA + (acoustic * 0.1);
    double local_rho   = BASE_RHO + (temp * 0.2);
    double local_beta  = perturb_beta(delta_t_s, vcap_mv);

    local_sigma = clamp_d(local_sigma, SIGMA_MIN, SIGMA_MAX);
    local_rho   = clamp_d(local_rho, RHO_MIN, RHO_MAX);

    for (int i = 0; i < ITERATIONS; i++) {
        double dx = local_sigma * (y - x);
        double dy = x * (local_rho - z) - y;
        double dz = (x * y) - (local_beta * z);

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

static double calculate_z_axis_from_seed(uint32_t seed, int8_t temp, uint8_t acoustic,
                                         uint16_t delta_t_s, uint16_t vcap_mv) {
    double x, y, z;
    seed_to_xyz(seed, &x, &y, &z);
    return calculate_z_axis(x, y, z, temp, acoustic, delta_t_s, vcap_mv);
}

/* StatusByte packing (matches bio_contract.rb BioContract.pack_status_byte).
 * `seed` is just a deterministic test-input generator (see seed_to_xyz).
 * [FW.29-PACK] Wire layout: [PanicFlag:1 (bit 7, 0 у normal) | Status:2 (bits 6..5) | GrowthPoints:5 (bits 4..0)].
 * growth_points у homeostasis отримує (reward / 2) щоб зберегти tokenomic
 * invariant після backend ×2 upscale (effective stored 10..62 vs old 10..63). */
static uint8_t evaluate_and_pack(uint32_t seed, int8_t temp, uint8_t acoustic) {
    double z_val = calculate_z_axis_from_seed(seed, temp, acoustic,
                                              BASELINE_DELTA_T_S, NOMINAL_VCAP_MV);

    int status = 0;
    int growth_points = 0;

    if (z_val < CRITICAL_Z_MIN) {
        status = BIO_STATUS_STRESS;
        growth_points = 1;
    } else if (z_val > CRITICAL_Z_MAX) {
        status = BIO_STATUS_ANOMALY;
        growth_points = 0;
    } else {
        status = BIO_STATUS_HOMEOSTASIS;
        double deviation = fabs(OPTIMAL_Z_TARGET - z_val);
        int reward = 50 - (int)round(deviation);
        growth_points = clamp_i(reward / 2, 5, 31);
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
    double z = calculate_z_axis_from_seed(12345, 20, 5, BASELINE_DELTA_T_S, NOMINAL_VCAP_MV);
    ASSERT(z > -100.0 && z < 100.0,
           "test_z_axis_normal_returns_finite");
}

static void test_z_axis_zero_seed(void) {
    /* Edge case: seed=0 */
    double z = calculate_z_axis_from_seed(0, 20, 5, BASELINE_DELTA_T_S, NOMINAL_VCAP_MV);
    ASSERT(!isnan(z) && !isinf(z),
           "test_z_axis_zero_seed_returns_valid");
}

static void test_z_axis_max_seed(void) {
    /* Edge case: seed=0xFFFFFFFF */
    double z = calculate_z_axis_from_seed(0xFFFFFFFF, 20, 5, BASELINE_DELTA_T_S, NOMINAL_VCAP_MV);
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

static void test_growth_points_max_31(void) {
    /* [FW.29-PACK] growth_points must never exceed 31 (5 bits) */
    int reward = 50 - 0; /* deviation=0 → reward=50, scaled /2 = 25, clamp to 5..31 */
    int gp = clamp_i(reward / 2, 5, 31);
    ASSERT(gp <= 31 && gp >= 5,
           "test_growth_points_max_31_min_5");
}

static void test_growth_points_min_5_homeostasis(void) {
    /* [FW.29-PACK] In homeostasis, minimum growth_points = 5 (after /2 scale) */
    /* deviation = 40 → reward = 50-40 = 10, scaled /2 = 5, clamped to 5..31 */
    int reward = 50 - 40;
    int gp = clamp_i(reward / 2, 5, 31);
    ASSERT(gp == 5,
           "test_growth_points_min_5_in_homeostasis");
}

static void test_evaluate_pack_normal(void) {
    /* Normal conditions should produce valid StatusByte */
    uint8_t result = evaluate_and_pack(12345, 20, 5);
    uint8_t status = (result >> 5) & 0x03;
    uint8_t gp = result & 0x1F;

    /* Status should be one of 0,1,2 */
    ASSERT(status <= 2,
           "test_evaluate_pack_valid_status");
    /* Growth points should be in valid range */
    ASSERT(gp <= 31,
           "test_evaluate_pack_valid_growth_points");
    /* PanicFlag (bit 7) must be clear in normal packets */
    ASSERT((result & 0x80) == 0,
           "test_evaluate_pack_panic_flag_clear");
}

static void test_evaluate_pack_stress_low_z(void) {
    /*
     * We need a seed/temp/acoustic combo that produces Z < 2.0 (stress).
     * With seed=0, temp=-45, acoustic=0: initial x=y=z ≈ -1.0,
     * sigma=10.0, rho=19.0 (28-9). Low rho can produce low Z.
     * The actual Z depends on chaotic dynamics; test that result is valid.
     */
    uint8_t result = evaluate_and_pack(0, -45, 0);
    uint8_t status = (result >> 5) & 0x03;
    uint8_t gp = result & 0x1F;
    ASSERT(status <= 2 && gp <= 31,
           "test_evaluate_pack_cold_zero_valid_result");
}

static void test_evaluate_pack_vm_error_byte(void) {
    /* [FW.29-PACK] BIO_STATUS_VM_ERROR = 0xFF — після backend `& 0x7F` mask
     * (PANIC_FLAG_BIT clear) залишається 0x7F, що декодує як status=3
     * (tamper, bits 6..5 = 11) + growth=31 (bits 4..0 = 11111).
     * До FW.29-PACK старе декодування давало status=1 (stress, bit 7 був 0
     * після mask, bits 7..6 = 01) + growth=63 — silent tamper demotion.  */
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
    double z1 = calculate_z_axis_from_seed(42, 25, 10, BASELINE_DELTA_T_S, NOMINAL_VCAP_MV);
    double z2 = calculate_z_axis_from_seed(42, 25, 10, BASELINE_DELTA_T_S, NOMINAL_VCAP_MV);
    ASSERT(fabs(z1 - z2) < 0.0001,
           "test_z_axis_deterministic_same_inputs");
}

static void test_z_axis_different_seeds(void) {
    /* Different seeds should (very likely) produce different Z */
    double z1 = calculate_z_axis_from_seed(100, 25, 10, BASELINE_DELTA_T_S, NOMINAL_VCAP_MV);
    double z2 = calculate_z_axis_from_seed(999, 25, 10, BASELINE_DELTA_T_S, NOMINAL_VCAP_MV);
    ASSERT(fabs(z1 - z2) > 0.001,
           "test_z_axis_different_seeds_different_z");
}

static void test_status_stress_growth_points_is_1(void) {
    /* When status is STRESS (z < 2.0), growth_points must be 1 */
    /* We verify the packing logic directly */
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
    double z_val = 50.0; /* above CRITICAL_Z_MAX */
    int status = 0, growth_points = 0;
    if (z_val < CRITICAL_Z_MIN) {
        status = BIO_STATUS_STRESS;
        growth_points = 1;
    } else if (z_val > CRITICAL_Z_MAX) {
        status = BIO_STATUS_ANOMALY;
        growth_points = 0;
    }
    ASSERT(status == BIO_STATUS_ANOMALY && growth_points == 0,
           "test_anomaly_zone_gives_0_growth_points");
}

static void test_homeostasis_optimal_z(void) {
    /* [FW.29-PACK] z_val == OPTIMAL_Z_TARGET → deviation=0 → reward=50 → wire = reward/2 clamped to [5,31] = 25 */
    double z_val = OPTIMAL_Z_TARGET;
    double deviation = fabs(OPTIMAL_Z_TARGET - z_val);
    int reward = 50 - (int)round(deviation);
    int gp = clamp_i(reward / 2, 5, 31);
    ASSERT(gp == 25,
           "test_homeostasis_optimal_z_gives_25_wire_points");
}

static void test_homeostasis_edge_z_min(void) {
    /* [FW.29-PACK] z_val == CRITICAL_Z_MIN → deviation = |29-2| = 27 → reward=23 → wire = reward/2 clamped to [5,31] = 11 */
    double z_val = CRITICAL_Z_MIN;
    double deviation = fabs(OPTIMAL_Z_TARGET - z_val);
    int reward = 50 - (int)round(deviation);
    int gp = clamp_i(reward / 2, 5, 31);
    ASSERT(gp == 11,
           "test_homeostasis_z_min_edge_gives_11_wire_points");
}

static void test_homeostasis_edge_z_max(void) {
    /* [FW.29-PACK] z_val == CRITICAL_Z_MAX → deviation = |29-45| = 16 → reward=34 → wire = reward/2 clamped to [5,31] = 17 */
    double z_val = CRITICAL_Z_MAX;
    double deviation = fabs(OPTIMAL_Z_TARGET - z_val);
    int reward = 50 - (int)round(deviation);
    int gp = clamp_i(reward / 2, 5, 31);
    ASSERT(gp == 17,
           "test_homeostasis_z_max_edge_gives_17_wire_points");
}

/* ════════════════════════════════════════════════════════════════════
 * BOUNDARY CONDITION TESTS
 * ════════════════════════════════════════════════════════════════════ */

static void test_extreme_temp_acoustic_combo(void) {
    /* Extreme combo: temp=-128 (int8_t min) + acoustic=255
     * sigma = 10.0 + 255*0.1 = 35.5 → clamped DOWN to 30.0
     * rho = 28.0 + (-128*0.2) = 28.0 - 25.6 = 2.4 → clamped UP to 10.0
     * Both parameters hit their clamp limits. Should produce valid (finite) Z. */
    double z = calculate_z_axis_from_seed(42, -128, 255, BASELINE_DELTA_T_S, NOMINAL_VCAP_MV);
    ASSERT(!isnan(z) && !isinf(z),
           "test_extreme_temp_minus128_acoustic_255_valid");
}

static void test_z_axis_sensitivity_to_temp(void) {
    /* Different temperatures with same seed/acoustic should produce different Z */
    double z_cold = calculate_z_axis_from_seed(42, -40, 5, BASELINE_DELTA_T_S, NOMINAL_VCAP_MV);
    double z_hot  = calculate_z_axis_from_seed(42, 80, 5, BASELINE_DELTA_T_S, NOMINAL_VCAP_MV);
    ASSERT(fabs(z_cold - z_hot) > 0.0001,
           "test_z_axis_different_temps_produce_different_z");
}

static void test_z_axis_sensitivity_to_acoustic(void) {
    /* Different acoustic values with same seed/temp should produce different Z */
    double z_quiet = calculate_z_axis_from_seed(42, 20, 0, BASELINE_DELTA_T_S, NOMINAL_VCAP_MV);
    double z_loud  = calculate_z_axis_from_seed(42, 20, 200, BASELINE_DELTA_T_S, NOMINAL_VCAP_MV);
    ASSERT(fabs(z_quiet - z_loud) > 0.0001,
           "test_z_axis_different_acoustics_produce_different_z");
}

static void test_growth_points_at_boundary_z(void) {
    /* Test growth points at exact boundary: z_val = 2.0 (CRITICAL_Z_MIN) */
    double z_val = CRITICAL_Z_MIN;
    int status, growth_points;
    if (z_val < CRITICAL_Z_MIN) {
        status = BIO_STATUS_STRESS;
        growth_points = 1;
    } else if (z_val > CRITICAL_Z_MAX) {
        status = BIO_STATUS_ANOMALY;
        growth_points = 0;
    } else {
        status = BIO_STATUS_HOMEOSTASIS;
        double deviation = fabs(OPTIMAL_Z_TARGET - z_val);
        int reward = 50 - (int)round(deviation);
        growth_points = clamp_i(reward / 2, 5, 31);  /* [FW.29-PACK] 5-bit wire */
    }
    /* z_val == 2.0 is NOT < 2.0, so it's homeostasis */
    ASSERT(status == BIO_STATUS_HOMEOSTASIS,
           "test_growth_points_at_z_min_boundary_is_homeostasis");

    /* Same for z_val = 45.0 (CRITICAL_Z_MAX) */
    z_val = CRITICAL_Z_MAX;
    if (z_val < CRITICAL_Z_MIN) {
        status = BIO_STATUS_STRESS;
        growth_points = 1;
    } else if (z_val > CRITICAL_Z_MAX) {
        status = BIO_STATUS_ANOMALY;
        growth_points = 0;
    } else {
        status = BIO_STATUS_HOMEOSTASIS;
        double deviation = fabs(OPTIMAL_Z_TARGET - z_val);
        int reward = 50 - (int)round(deviation);
        growth_points = clamp_i(reward / 2, 5, 31);  /* [FW.29-PACK] 5-bit wire */
    }
    /* z_val == 45.0 is NOT > 45.0, so it's homeostasis */
    ASSERT(status == BIO_STATUS_HOMEOSTASIS,
           "test_growth_points_at_z_max_boundary_is_homeostasis");
}

static void test_evaluate_pack_deterministic_across_range(void) {
    /* Multiple evaluations with same input must return identical result */
    for (uint32_t seed = 0; seed < 1000; seed += 100) {
        uint8_t r1 = evaluate_and_pack(seed, 20, 5);
        uint8_t r2 = evaluate_and_pack(seed, 20, 5);
        if (r1 != r2) {
            ASSERT(0, "test_evaluate_pack_not_deterministic");
            return;
        }
    }
    ASSERT(1, "test_evaluate_pack_deterministic_10_seeds");
}

/* ════════════════════════════════════════════════════════════════════
 * [FW.5] β-PERTURBATION FROM EBFC METABOLISM (delta_t / vcap)
 * ════════════════════════════════════════════════════════════════════ */

static void test_beta_perturbation_baseline_returns_classic(void) {
    /* delta_t = baseline (60 s), vcap = nominal (3300 mV) → β = 8/3 */
    double beta = perturb_beta(BASELINE_DELTA_T_S, NOMINAL_VCAP_MV);
    ASSERT(fabs(beta - (8.0 / 3.0)) < 1e-15,
           "test_beta_baseline_equals_classic_8_div_3");
}

static void test_beta_perturbation_faster_charge_increases_beta(void) {
    /* delta_t = 30 s (30 s improvement vs 60 s baseline) → β += 30 * 0.0001 = +0.003 */
    double beta = perturb_beta(30, NOMINAL_VCAP_MV);
    double expected = (8.0 / 3.0) + 30.0 * 0.0001;
    ASSERT(fabs(beta - expected) < 1e-15,
           "test_beta_faster_charge_30s_adds_0_003");
}

static void test_beta_perturbation_slower_charge_no_decrease(void) {
    /* delta_t = 120 s (slower than baseline) → improvement clamped to 0 → β unchanged */
    double beta = perturb_beta(120, NOMINAL_VCAP_MV);
    ASSERT(fabs(beta - (8.0 / 3.0)) < 1e-15,
           "test_beta_slower_charge_clamped_to_baseline");
}

static void test_beta_perturbation_high_vcap_increases_beta(void) {
    /* vcap = 3500 mV (200 mV above nominal) → β += 200 * 0.001 = +0.2 */
    double beta = perturb_beta(BASELINE_DELTA_T_S, 3500);
    double expected = (8.0 / 3.0) + 200.0 * 0.001;
    ASSERT(fabs(beta - expected) < 1e-15,
           "test_beta_high_vcap_adds_0_2");
}

static void test_beta_perturbation_low_vcap_decreases_beta(void) {
    /* vcap = 3000 mV (300 mV below nominal) → β -= 300 * 0.001 = -0.3 */
    double beta = perturb_beta(BASELINE_DELTA_T_S, 3000);
    double expected = (8.0 / 3.0) - 300.0 * 0.001;
    ASSERT(fabs(beta - expected) < 1e-15,
           "test_beta_low_vcap_subtracts_0_3");
}

static void test_beta_perturbation_clamped_to_max(void) {
    /* Extreme: delta_t = 0 (60 s improvement), vcap = 5000 (1700 mV above)
     * β += 60*0.0001 + 1700*0.001 = 0.006 + 1.7 = 1.706
     * raw = 8/3 + 1.706 = 4.373 → clamped to 4.0 */
    double beta = perturb_beta(0, 5000);
    ASSERT(fabs(beta - BETA_MAX) < 1e-15,
           "test_beta_extreme_high_clamped_to_4_0");
}

static void test_beta_perturbation_clamped_to_min(void) {
    /* Extreme low vcap: delta_t = 60 (no improvement), vcap = 0 (3300 mV below)
     * β -= 3300*0.001 = -3.3 → raw = 8/3 - 3.3 = -0.633 → clamped to 2.0 */
    double beta = perturb_beta(BASELINE_DELTA_T_S, 0);
    ASSERT(fabs(beta - BETA_MIN) < 1e-15,
           "test_beta_extreme_low_clamped_to_2_0");
}

static void test_z_axis_metabolism_changes_z(void) {
    /* Same chaotic seed/temp/acoustic, but different metabolism:
     * fast (high β) vs slow (baseline β) — Z trajectories diverge */
    double z_fast = calculate_z_axis_from_seed(42, 20, 5, 10, 3500);   /* 50 s improvement, +200 mV */
    double z_baseline = calculate_z_axis_from_seed(42, 20, 5, BASELINE_DELTA_T_S, NOMINAL_VCAP_MV);
    ASSERT(fabs(z_fast - z_baseline) > 0.0001,
           "test_z_axis_metabolism_inputs_change_trajectory");
}

static void test_z_axis_finite_under_extreme_metabolism(void) {
    /* Even with extreme metabolism inputs, β is clamped → trajectory bounded */
    double z = calculate_z_axis_from_seed(42, 20, 5, 0, 0xFFFF);
    ASSERT(!isnan(z) && !isinf(z),
           "test_z_axis_extreme_metabolism_stays_finite");
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

    printf("\n  Growth Points Logic:\n");
    test_growth_points_max_31();
    test_growth_points_min_5_homeostasis();
    test_status_stress_growth_points_is_1();
    test_status_anomaly_growth_points_is_0();
    test_homeostasis_optimal_z();
    test_homeostasis_edge_z_min();
    test_homeostasis_edge_z_max();

    printf("\n  Evaluate & Pack (Integration):\n");
    test_evaluate_pack_normal();
    test_evaluate_pack_stress_low_z();

    printf("\n  Boundary Conditions:\n");
    test_extreme_temp_acoustic_combo();
    test_z_axis_sensitivity_to_temp();
    test_z_axis_sensitivity_to_acoustic();
    test_growth_points_at_boundary_z();
    test_evaluate_pack_deterministic_across_range();

    printf("\n  [FW.5] β-Perturbation from EBFC Metabolism:\n");
    test_beta_perturbation_baseline_returns_classic();
    test_beta_perturbation_faster_charge_increases_beta();
    test_beta_perturbation_slower_charge_no_decrease();
    test_beta_perturbation_high_vcap_increases_beta();
    test_beta_perturbation_low_vcap_decreases_beta();
    test_beta_perturbation_clamped_to_max();
    test_beta_perturbation_clamped_to_min();
    test_z_axis_metabolism_changes_z();
    test_z_axis_finite_under_extreme_metabolism();

    printf("\n══════════════════════════════════════════════════════════════\n");
    printf("  Results: %d passed, %d failed\n", tests_passed, tests_failed);
    printf("══════════════════════════════════════════════════════════════\n\n");

    return tests_failed > 0 ? 1 : 0;
}
