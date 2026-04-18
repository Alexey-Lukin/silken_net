/*
 * test_bio_contract.c — Host-based unit tests for bio-contract logic.
 *
 * Tests the Lorenz attractor math and StatusByte packing that run on
 * the Soldier MCU via mruby. Since mruby is not available on the host,
 * we re-implement the pure-math functions in C and verify:
 *   - Sigma/Rho clamping boundaries
 *   - Z-axis bounds (CRITICAL_Z_MIN=2.0, CRITICAL_Z_MAX=45.0)
 *   - Growth points calculation and 6-bit packing
 *   - StatusByte encoding: [status:2 | growth_points:6]
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

/* Lorenz attractor Z-axis calculation (matches bio_contract.rb Attractor.calculate_z_axis) */
static double calculate_z_axis(uint32_t seed, int8_t temp, uint8_t acoustic) {
    double x = ((double)(seed % 1000) / 500.0) - 1.0;
    double y = ((double)((seed >> 4) % 1000) / 500.0) - 1.0;
    double z = ((double)((seed >> 8) % 1000) / 500.0) - 1.0;

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

/* StatusByte packing (matches bio_contract.rb BioContract.evaluate_and_pack) */
static uint8_t evaluate_and_pack(uint32_t seed, int8_t temp, uint8_t acoustic) {
    double z_val = calculate_z_axis(seed, temp, acoustic);

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
        growth_points = clamp_i(reward, 10, 63);
    }

    growth_points = clamp_i(growth_points, 0, 63);

    return (uint8_t)((status << 6) | growth_points);
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
    double z = calculate_z_axis(12345, 20, 5);
    ASSERT(z > -100.0 && z < 100.0,
           "test_z_axis_normal_returns_finite");
}

static void test_z_axis_zero_seed(void) {
    /* Edge case: seed=0 */
    double z = calculate_z_axis(0, 20, 5);
    ASSERT(!isnan(z) && !isinf(z),
           "test_z_axis_zero_seed_returns_valid");
}

static void test_z_axis_max_seed(void) {
    /* Edge case: seed=0xFFFFFFFF */
    double z = calculate_z_axis(0xFFFFFFFF, 20, 5);
    ASSERT(!isnan(z) && !isinf(z),
           "test_z_axis_max_seed_returns_valid");
}

static void test_status_byte_encoding(void) {
    /* Verify bit layout: [status:2 | growth_points:6] */
    uint8_t byte1 = (BIO_STATUS_HOMEOSTASIS << 6) | 50;
    ASSERT((byte1 >> 6) == 0 && (byte1 & 0x3F) == 50,
           "test_status_byte_homeostasis_50pts");

    uint8_t byte2 = (BIO_STATUS_STRESS << 6) | 1;
    ASSERT((byte2 >> 6) == 1 && (byte2 & 0x3F) == 1,
           "test_status_byte_stress_1pt");

    uint8_t byte3 = (BIO_STATUS_ANOMALY << 6) | 0;
    ASSERT((byte3 >> 6) == 2 && (byte3 & 0x3F) == 0,
           "test_status_byte_anomaly_0pts");
}

static void test_growth_points_max_63(void) {
    /* growth_points must never exceed 63 (6 bits) */
    int reward = 50 - 0; /* deviation=0 → reward=50 */
    int gp = clamp_i(reward, 10, 63);
    ASSERT(gp <= 63 && gp >= 10,
           "test_growth_points_max_63_min_10");
}

static void test_growth_points_min_10_homeostasis(void) {
    /* In homeostasis, minimum growth_points = 10 */
    /* deviation = 40 → reward = 50-40 = 10, clamped to 10 */
    int reward = 50 - 40;
    int gp = clamp_i(reward, 10, 63);
    ASSERT(gp == 10,
           "test_growth_points_min_10_in_homeostasis");
}

static void test_evaluate_pack_normal(void) {
    /* Normal conditions should produce valid StatusByte */
    uint8_t result = evaluate_and_pack(12345, 20, 5);
    uint8_t status = result >> 6;
    uint8_t gp = result & 0x3F;

    /* Status should be one of 0,1,2 */
    ASSERT(status <= 2,
           "test_evaluate_pack_valid_status");
    /* Growth points should be in valid range */
    ASSERT(gp <= 63,
           "test_evaluate_pack_valid_growth_points");
}

static void test_evaluate_pack_stress_low_z(void) {
    /*
     * We need a seed/temp/acoustic combo that produces Z < 2.0 (stress).
     * With seed=0, temp=-45, acoustic=0: initial x=y=z ≈ -1.0,
     * sigma=10.0, rho=19.0 (28-9). Low rho can produce low Z.
     * The actual Z depends on chaotic dynamics; test that result is valid.
     */
    uint8_t result = evaluate_and_pack(0, -45, 0);
    uint8_t status = result >> 6;
    uint8_t gp = result & 0x3F;
    ASSERT(status <= 2 && gp <= 63,
           "test_evaluate_pack_cold_zero_valid_result");
}

static void test_evaluate_pack_vm_error_byte(void) {
    /* BIO_STATUS_VM_ERROR = 0xFF means status=3 (tamper) + gp=63 */
    uint8_t vm_error = 0xFF;
    ASSERT((vm_error >> 6) == 3 && (vm_error & 0x3F) == 63,
           "test_vm_error_byte_0xFF_decodes_correctly");
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
    double z1 = calculate_z_axis(42, 25, 10);
    double z2 = calculate_z_axis(42, 25, 10);
    ASSERT(fabs(z1 - z2) < 0.0001,
           "test_z_axis_deterministic_same_inputs");
}

static void test_z_axis_different_seeds(void) {
    /* Different seeds should (very likely) produce different Z */
    double z1 = calculate_z_axis(100, 25, 10);
    double z2 = calculate_z_axis(999, 25, 10);
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
    /* z_val == OPTIMAL_Z_TARGET → deviation=0 → reward=50, clamped to [10,63] */
    double z_val = OPTIMAL_Z_TARGET;
    double deviation = fabs(OPTIMAL_Z_TARGET - z_val);
    int reward = 50 - (int)round(deviation);
    int gp = clamp_i(reward, 10, 63);
    ASSERT(gp == 50,
           "test_homeostasis_optimal_z_gives_50_points");
}

static void test_homeostasis_edge_z_min(void) {
    /* z_val == CRITICAL_Z_MIN → deviation = |29-2| = 27 → reward=23, clamped to [10,63] */
    double z_val = CRITICAL_Z_MIN;
    double deviation = fabs(OPTIMAL_Z_TARGET - z_val);
    int reward = 50 - (int)round(deviation);
    int gp = clamp_i(reward, 10, 63);
    ASSERT(gp == 23,
           "test_homeostasis_z_min_edge_gives_23_points");
}

static void test_homeostasis_edge_z_max(void) {
    /* z_val == CRITICAL_Z_MAX → deviation = |29-45| = 16 → reward=34, clamped to [10,63] */
    double z_val = CRITICAL_Z_MAX;
    double deviation = fabs(OPTIMAL_Z_TARGET - z_val);
    int reward = 50 - (int)round(deviation);
    int gp = clamp_i(reward, 10, 63);
    ASSERT(gp == 34,
           "test_homeostasis_z_max_edge_gives_34_points");
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
    test_growth_points_max_63();
    test_growth_points_min_10_homeostasis();
    test_status_stress_growth_points_is_1();
    test_status_anomaly_growth_points_is_0();
    test_homeostasis_optimal_z();
    test_homeostasis_edge_z_min();
    test_homeostasis_edge_z_max();

    printf("\n  Evaluate & Pack (Integration):\n");
    test_evaluate_pack_normal();
    test_evaluate_pack_stress_low_z();

    printf("\n══════════════════════════════════════════════════════════════\n");
    printf("  Results: %d passed, %d failed\n", tests_passed, tests_failed);
    printf("══════════════════════════════════════════════════════════════\n\n");

    return tests_failed > 0 ? 1 : 0;
}
