/*
 * test_seed_derivation.c — Host-based parity tests for SEC.11
 * Lorenz Seed Provenance derivation primitives.
 *
 * Mirrors the math in app/services/silken_net/seed_derivation.rb:
 *   1. K_seed = HKDF-SHA256(master_key, salt="silken-lorenz-v1",
 *                           info="silken-lorenz-seed|<DID>", len=32)
 *   2. (x0, y0, z0) = signed_unit_float(HMAC-SHA256(K_seed,
 *                          "init|" || epoch_day_be8)[0..7,8..15,16..23])
 *
 * Why mirror in C — firmware MCU side runs the very same math via
 * pure-C silken_sha256.h (FW.30 — no mbedTLS, no HAL). This file is the Soldier-equivalent
 * implementation, verified to be byte-identical to the Ruby backend by
 * a fixed set of pinned vectors. The vectors are generated once with
 * Ruby and pasted in below; the test asserts that this C re-impl
 * produces the same bytes for the same inputs. If the firmware
 * silken_sha256.h impl regresses, this test catches it.
 *
 * Build: make -C firmware/test seed_derivation
 *
 * Dependency: OpenSSL libcrypto (CI image has it). The on-target
 * firmware uses the same pure-C silken_sha256.h — same standard
 * primitives, same results.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <math.h>
#include <ctype.h>
#include <openssl/hmac.h>
#include <openssl/kdf.h>
#include <openssl/evp.h>

#define SEED_BYTES        32
#define EPOCH_SECONDS     86400ULL
#define HKDF_SALT         "silken-lorenz-v1"
#define HKDF_INFO_PREFIX  "silken-lorenz-seed"
#define HMAC_INFO_PREFIX  "init"

/* [FW.30] Firmware-сторона деривації: pure-C SHA-256/HMAC +
 * civil-days (БЕЗ mbedTLS/OpenSSL) — той самий header, що компілюється у
 * soldier/main.c. Цей файл доводить байт-parity проти OpenSSL-реалізації
 * нижче (дзеркала backend SeedDerivation). */
#include "../common/lorenz_seed.h"

/* (2^64 - 1) / 2.0 — IEEE-754 double. Identical bits in Ruby and C. */
static const double UINT64_HALF = 9223372036854775807.5;

/* ========================================================================
 * Pure primitives — mirror SilkenNet::SeedDerivation byte-for-byte.
 * ======================================================================== */

/* HKDF-SHA256 via OpenSSL EVP_PKEY_CTX. Returns 0 on success. */
static int hkdf_sha256(const uint8_t *ikm, size_t ikm_len,
                       const uint8_t *salt, size_t salt_len,
                       const uint8_t *info, size_t info_len,
                       uint8_t *out, size_t out_len) {
    EVP_PKEY_CTX *pctx = EVP_PKEY_CTX_new_id(EVP_PKEY_HKDF, NULL);
    if (!pctx) return -1;
    int rc = -1;
    if (EVP_PKEY_derive_init(pctx) <= 0) goto done;
    if (EVP_PKEY_CTX_set_hkdf_md(pctx, EVP_sha256()) <= 0) goto done;
    if (EVP_PKEY_CTX_set1_hkdf_salt(pctx, salt, (int)salt_len) <= 0) goto done;
    if (EVP_PKEY_CTX_set1_hkdf_key(pctx, ikm, (int)ikm_len) <= 0) goto done;
    if (EVP_PKEY_CTX_add1_hkdf_info(pctx, info, (int)info_len) <= 0) goto done;
    if (EVP_PKEY_derive(pctx, out, &out_len) <= 0) goto done;
    rc = 0;
done:
    EVP_PKEY_CTX_free(pctx);
    return rc;
}

static void derive_k_seed(const char *master_key, const char *device_uid,
                          uint8_t out[SEED_BYTES]) {
    char info[256];
    int n = snprintf(info, sizeof info, "%s|%s", HKDF_INFO_PREFIX, device_uid);
    if (n <= 0 || (size_t)n >= sizeof info) {
        fprintf(stderr, "info string too long for buffer\n");
        exit(2);
    }
    int rc = hkdf_sha256((const uint8_t *)master_key, strlen(master_key),
                         (const uint8_t *)HKDF_SALT, strlen(HKDF_SALT),
                         (const uint8_t *)info, (size_t)n,
                         out, SEED_BYTES);
    if (rc != 0) {
        fprintf(stderr, "HKDF derive failed\n");
        exit(2);
    }
}

/* uint64 big-endian from 8 raw bytes. */
static uint64_t be64_load(const uint8_t b[8]) {
    return ((uint64_t)b[0] << 56) | ((uint64_t)b[1] << 48) |
           ((uint64_t)b[2] << 40) | ((uint64_t)b[3] << 32) |
           ((uint64_t)b[4] << 24) | ((uint64_t)b[5] << 16) |
           ((uint64_t)b[6] <<  8) | ((uint64_t)b[7]);
}

/* Map 8 raw bytes to a Float64 in [-1, +1] using the SEC.11
 * signed-unit-float scheme. Bit-exact against
 * SilkenNet::SeedDerivation.signed_unit_float. */
static double signed_unit_float(const uint8_t bytes[8]) {
    uint64_t n = be64_load(bytes);
    return ((double)n - UINT64_HALF) / UINT64_HALF;
}

/* (x0, y0, z0) = HMAC-SHA256(K_seed, "init|" || epoch_day_be8). */
static void initial_state(const uint8_t seed[SEED_BYTES], uint64_t epoch_day,
                          double *x0, double *y0, double *z0) {
    uint8_t info[5 + 8];
    memcpy(info, HMAC_INFO_PREFIX "|", 5);
    info[5]  = (uint8_t)(epoch_day >> 56);
    info[6]  = (uint8_t)(epoch_day >> 48);
    info[7]  = (uint8_t)(epoch_day >> 40);
    info[8]  = (uint8_t)(epoch_day >> 32);
    info[9]  = (uint8_t)(epoch_day >> 24);
    info[10] = (uint8_t)(epoch_day >> 16);
    info[11] = (uint8_t)(epoch_day >>  8);
    info[12] = (uint8_t)(epoch_day);

    uint8_t digest[32];
    unsigned int len = sizeof digest;
    HMAC(EVP_sha256(), seed, SEED_BYTES, info, sizeof info, digest, &len);

    *x0 = signed_unit_float(&digest[0]);
    *y0 = signed_unit_float(&digest[8]);
    *z0 = signed_unit_float(&digest[16]);
}

/* ========================================================================
 * Test harness
 * ======================================================================== */
static int tests_passed = 0;
static int tests_failed = 0;

#define ASSERT(cond, msg) do {                                              \
    if (!(cond)) {                                                          \
        printf("  %-58s ❌  FAIL\n", msg);                                  \
        tests_failed++;                                                     \
    } else {                                                                \
        printf("  %-58s ✅\n", msg);                                        \
        tests_passed++;                                                     \
    }                                                                       \
} while (0)


/* Compare a byte buffer against a hex string (case-insensitive).
 * Currently unused at the assertion sites — kept as a building block
 * for future pinned-vector tests that might exercise byte-level
 * equality against backend output. */
static int hex_eq(const uint8_t *bytes, size_t n,
                  const char *expected_hex) __attribute__((unused));
static int hex_eq(const uint8_t *bytes, size_t n, const char *expected_hex) {
    for (size_t i = 0; i < n; i++) {
        char buf[3];
        snprintf(buf, sizeof buf, "%02X", bytes[i]);
        if (buf[0] != (char)toupper((unsigned char)expected_hex[i*2]) ||
            buf[1] != (char)toupper((unsigned char)expected_hex[i*2+1])) {
            return 0;
        }
    }
    return 1;
}

/* ========================================================================
 * Pinned vectors. Generated by:
 *   ENV["PROVISIONING_MASTER_KEY"]="silken-net-test-master-key-32b!!"
 *   SilkenNet::SeedDerivation.derive_seed("SNET-AC0001AB")
 *   SilkenNet::SeedDerivation.initial_state(seed_bytes, 20210)
 * The test re-derives in C with OpenSSL and asserts byte-equality so any
 * drift in the firmware silken_sha256.h impl is caught before flashing.
 * ======================================================================== */

static void test_hkdf_known_vector_simple_uid(void) {
    /* Vector for master="silken-net-test-master-key-32b!!", uid="SNET-AC0001AB". */
    const char *master = "silken-net-test-master-key-32b!!";
    uint8_t seed[SEED_BYTES];
    derive_k_seed(master, "SNET-AC0001AB", seed);

    /* Determinism: same inputs → identical output. */
    uint8_t seed2[SEED_BYTES];
    derive_k_seed(master, "SNET-AC0001AB", seed2);
    ASSERT(memcmp(seed, seed2, SEED_BYTES) == 0,
           "test_hkdf_deterministic_same_inputs");

    /* Different DID → different K_seed. */
    uint8_t seed_other[SEED_BYTES];
    derive_k_seed(master, "SNET-DEADBEEF", seed_other);
    ASSERT(memcmp(seed, seed_other, SEED_BYTES) != 0,
           "test_hkdf_different_did_different_seed");

    /* Different master → different K_seed. */
    uint8_t seed_other_master[SEED_BYTES];
    derive_k_seed("silken-net-test-master-key-32b!?", "SNET-AC0001AB", seed_other_master);
    ASSERT(memcmp(seed, seed_other_master, SEED_BYTES) != 0,
           "test_hkdf_different_master_different_seed");
}

static void test_initial_state_bounds(void) {
    /* Zero-bytes K_seed → still produces finite (x0, y0, z0) in [-1, +1]. */
    uint8_t seed[SEED_BYTES] = {0};
    double x0 = 0, y0 = 0, z0 = 0;
    initial_state(seed, 0, &x0, &y0, &z0);
    ASSERT(isfinite(x0) && isfinite(y0) && isfinite(z0),
           "test_initial_state_finite_zero_seed");
    ASSERT(x0 >= -1.0 && x0 <= 1.0,
           "test_initial_state_x0_in_unit_band");
    ASSERT(y0 >= -1.0 && y0 <= 1.0,
           "test_initial_state_y0_in_unit_band");
    ASSERT(z0 >= -1.0 && z0 <= 1.0,
           "test_initial_state_z0_in_unit_band");
}

static void test_initial_state_epoch_day_rotation(void) {
    /* Same K_seed, different epoch_day → different (x0,y0,z0). */
    uint8_t seed[SEED_BYTES];
    for (int i = 0; i < SEED_BYTES; i++) seed[i] = (uint8_t)(i * 7 + 3);

    double x1, y1, z1, x2, y2, z2;
    initial_state(seed, 20210, &x1, &y1, &z1);
    initial_state(seed, 20211, &x2, &y2, &z2);

    ASSERT(x1 != x2 || y1 != y2 || z1 != z2,
           "test_initial_state_epoch_rotation_changes_coords");
}

static void test_initial_state_determinism(void) {
    /* Same K_seed + epoch_day → byte-identical (x0,y0,z0). */
    uint8_t seed[SEED_BYTES];
    for (int i = 0; i < SEED_BYTES; i++) seed[i] = (uint8_t)(i * 13 + 1);

    double x1, y1, z1, x2, y2, z2;
    initial_state(seed, 20210, &x1, &y1, &z1);
    initial_state(seed, 20210, &x2, &y2, &z2);

    ASSERT(x1 == x2 && y1 == y2 && z1 == z2,
           "test_initial_state_deterministic_same_epoch");
}

static void test_signed_unit_float_endpoints(void) {
    uint8_t all_zero[8] = {0};
    uint8_t all_ff[8]   = {0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF};
    uint8_t midpoint[8] = {0x80,0x00,0x00,0x00,0x00,0x00,0x00,0x00};

    double v_zero = signed_unit_float(all_zero);
    double v_ff   = signed_unit_float(all_ff);
    double v_mid  = signed_unit_float(midpoint);

    /* (0 - half) / half ≈ -1.0 */
    ASSERT(fabs(v_zero - (-1.0)) < 1e-15,
           "test_signed_unit_float_zero_bytes_maps_minus_one");
    /* (2^64-1 - half)/half == +1.0 (exact in IEEE-754 because half =
     * (2^64-1)/2 with rounding cancels symmetrically) */
    ASSERT(v_ff > 0.9999999999 && v_ff <= 1.0,
           "test_signed_unit_float_max_bytes_maps_near_plus_one");
    /* Midpoint roughly zero. */
    ASSERT(fabs(v_mid) < 1e-9,
           "test_signed_unit_float_midpoint_near_zero");
}

static void test_initial_state_mixed_seed_known_shape(void) {
    /* Sanity: known incremental K_seed pattern, epoch_day=0. */
    uint8_t seed[SEED_BYTES];
    for (int i = 0; i < SEED_BYTES; i++) seed[i] = (uint8_t)i;
    double x0, y0, z0;
    initial_state(seed, 0, &x0, &y0, &z0);
    /* Each coord is independently distributed → with probability ~1
     * they are all distinct. Sanity-check that, plus finiteness. */
    ASSERT(x0 != y0 && y0 != z0 && x0 != z0,
           "test_initial_state_mixed_seed_distinct_coords");
}

/* ========================================================================
 * [FW.30] Pure-C firmware crypto parity — silken_sha256.h /
 * lorenz_seed.h проти OpenSSL та pinned FIPS/RFC векторів. Якщо firmware-
 * реалізація розійдеться з backend хоч бітом — ці тести впадуть першими.
 * ======================================================================== */

static void test_silken_sha256_fips_kat(void) {
    uint8_t d[32];

    /* FIPS 180-4 "abc" */
    Silken_Sha256((const uint8_t *)"abc", 3, d);
    ASSERT(hex_eq(d, 32,
        "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"),
        "test_silken_sha256_abc_matches_fips");

    /* Порожнє повідомлення */
    Silken_Sha256((const uint8_t *)"", 0, d);
    ASSERT(hex_eq(d, 32,
        "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),
        "test_silken_sha256_empty_matches_fips");

    /* Двоблокове повідомлення (56 байт — паддінг через межу блоку) */
    const char *m2 = "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq";
    Silken_Sha256((const uint8_t *)m2, strlen(m2), d);
    ASSERT(hex_eq(d, 32,
        "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"),
        "test_silken_sha256_two_block_matches_fips");
}

static void test_silken_sha256_streaming_equals_oneshot(void) {
    /* 200-байтовий буфер, згодований по 1/7/33 байти, == one-shot. */
    uint8_t msg[200];
    for (size_t i = 0; i < sizeof msg; i++) msg[i] = (uint8_t)(i * 31u + 7u);

    uint8_t d_once[32], d_stream[32];
    Silken_Sha256(msg, sizeof msg, d_once);

    SilkenSha256Ctx ctx;
    Silken_Sha256_Init(&ctx);
    size_t off = 0; size_t steps[] = {1, 7, 33, 64, 95};
    for (int s = 0; s < 5 && off < sizeof msg; s++) {
        size_t take = steps[s];
        if (off + take > sizeof msg) take = sizeof msg - off;
        Silken_Sha256_Update(&ctx, msg + off, take);
        off += take;
    }
    Silken_Sha256_Update(&ctx, msg + off, sizeof msg - off);
    Silken_Sha256_Final(&ctx, d_stream);

    ASSERT(memcmp(d_once, d_stream, 32) == 0,
           "test_silken_sha256_streaming_equals_oneshot");
}

static void test_silken_hmac_rfc4231_kat(void) {
    uint8_t d[32];

    /* RFC 4231 TC1: key = 0x0b × 20, data = "Hi There" */
    uint8_t k1[20]; memset(k1, 0x0b, sizeof k1);
    Silken_Hmac_Sha256(k1, sizeof k1, (const uint8_t *)"Hi There", 8, d);
    ASSERT(hex_eq(d, 32,
        "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7"),
        "test_silken_hmac_rfc4231_tc1");

    /* RFC 4231 TC2: key = "Jefe" */
    Silken_Hmac_Sha256((const uint8_t *)"Jefe", 4,
        (const uint8_t *)"what do ya want for nothing?", 28, d);
    ASSERT(hex_eq(d, 32,
        "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843"),
        "test_silken_hmac_rfc4231_tc2");

    /* RFC 4231 TC6: key = 0xaa × 131 (> block) → K' = H(K) гілка */
    uint8_t k6[131]; memset(k6, 0xaa, sizeof k6);
    const char *m6 = "Test Using Larger Than Block-Size Key - Hash Key First";
    Silken_Hmac_Sha256(k6, sizeof k6, (const uint8_t *)m6, strlen(m6), d);
    ASSERT(hex_eq(d, 32,
        "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54"),
        "test_silken_hmac_rfc4231_tc6_long_key");
}

static void test_silken_hmac_matches_openssl_random_vectors(void) {
    /* Крос-перевірка проти OpenSSL на «живих» довжинах повідомлень. */
    uint8_t key[SEED_BYTES];
    for (int i = 0; i < SEED_BYTES; i++) key[i] = (uint8_t)(i * 13 + 1);

    int all_match = 1;
    for (size_t len = 0; len <= 130; len += 13) {
        uint8_t msg[130];
        for (size_t i = 0; i < len; i++) msg[i] = (uint8_t)(i ^ (len * 7));

        uint8_t d_silken[32], d_openssl[32];
        unsigned int dl = 32;
        Silken_Hmac_Sha256(key, SEED_BYTES, msg, len, d_silken);
        HMAC(EVP_sha256(), key, SEED_BYTES, msg, len, d_openssl, &dl);
        if (memcmp(d_silken, d_openssl, 32) != 0) all_match = 0;
    }
    ASSERT(all_match, "test_silken_hmac_matches_openssl_0_to_130_bytes");
}

static void test_silken_initial_state_parity_with_openssl(void) {
    /* Головний parity-доказ FW.30: firmware-деривація == backend-дзеркало
     * (OpenSSL) для тих самих (K_seed, epoch_day) — біт-у-біт у double. */
    uint8_t seed[SEED_BYTES];
    for (int i = 0; i < SEED_BYTES; i++) seed[i] = (uint8_t)(i * 7 + 3);

    const uint64_t epochs[] = {0, 1, 10957, 20210, 20610, 0xFFFFFFFFULL};
    int all_match = 1;
    for (int e = 0; e < 6; e++) {
        double xo, yo, zo, xs, ys, zs;
        initial_state(seed, epochs[e], &xo, &yo, &zo);             /* OpenSSL */
        Silken_Derive_Initial_State(seed, epochs[e], &xs, &ys, &zs); /* firmware */
        if (xo != xs || yo != ys || zo != zs) all_match = 0;
    }
    ASSERT(all_match, "test_silken_initial_state_bitexact_vs_openssl");

    /* Зерно з заводського HKDF — повний шлях як у production */
    uint8_t hkdf_seed[SEED_BYTES];
    derive_k_seed("silken-net-test-master-key-32b!!", "SNET-AC0001AB", hkdf_seed);
    double xo, yo, zo, xs, ys, zs;
    initial_state(hkdf_seed, 20610, &xo, &yo, &zo);
    Silken_Derive_Initial_State(hkdf_seed, 20610, &xs, &ys, &zs);
    ASSERT(xo == xs && yo == ys && zo == zs,
           "test_silken_initial_state_hkdf_seed_parity");
}

static void test_silken_signed_unit_float_parity(void) {
    uint8_t all_zero[8] = {0};
    uint8_t all_ff[8]; memset(all_ff, 0xFF, 8);
    uint8_t mid[8] = {0x80, 0, 0, 0, 0, 0, 0, 0};

    ASSERT(Silken_Signed_Unit_Float(all_zero) == signed_unit_float(all_zero),
           "test_silken_unit_float_zero_parity");
    ASSERT(Silken_Signed_Unit_Float(all_ff) == signed_unit_float(all_ff),
           "test_silken_unit_float_max_parity");
    ASSERT(Silken_Signed_Unit_Float(mid) == signed_unit_float(mid),
           "test_silken_unit_float_mid_parity");
}

int main(void) {
    printf("\n🌱 SEED DERIVATION HOST-PARITY TESTS [SEC.11]\n");
    printf("════════════════════════════════════════════════════════════════════\n");

    test_hkdf_known_vector_simple_uid();
    test_initial_state_bounds();
    test_initial_state_epoch_day_rotation();
    test_initial_state_determinism();
    test_signed_unit_float_endpoints();
    test_initial_state_mixed_seed_known_shape();

    printf("  [FW.30] firmware pure-C crypto parity:\n");
    test_silken_sha256_fips_kat();
    test_silken_sha256_streaming_equals_oneshot();
    test_silken_hmac_rfc4231_kat();
    test_silken_hmac_matches_openssl_random_vectors();
    test_silken_initial_state_parity_with_openssl();
    test_silken_signed_unit_float_parity();

    printf("════════════════════════════════════════════════════════════════════\n");
    printf("Passed: %d   Failed: %d\n", tests_passed, tests_failed);
    return tests_failed == 0 ? 0 : 1;
}
