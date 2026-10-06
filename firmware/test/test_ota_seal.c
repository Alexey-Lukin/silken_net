// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * test_ota_seal.c — [FW.23, ⚖️ founder 2026-10-05/06] Ed25519-печатка OTA-контракту:
 * паритет поза самим Monocypher (скіл firmware: нова криптографія в common/ — звір її
 * з OpenSSL, а не копіюй логіку в тест).
 *   1. Золотий вектор, підписаний Ruby-пакувальником (OtaPackagerService → гем ed25519):
 *      Ota_Seal_Verify прошивки, crypto_ed25519_check і OpenSSL кажуть «так» тому самому
 *      підпису — тобто бекенд і Солдат погоджуються щодо формату повідомлення й ключа.
 *      ⚠️ Ті самі байти живуть у spec/services/ota_packager_service_spec.rb (міняєш тут →
 *      перегенеруй там, і навпаки).
 *   2. OpenSSL (EVP Ed25519) — незалежний підписувач і перевіряльник для тих самих ключів.
 *   3. Стрімінг тіло ‖ суфікс у Ota_Seal_Verify ≡ crypto_ed25519_check над склеєним
 *      повідомленням — на будь-якій точці розрізу, для справжніх і зіпсованих підписів.
 *   4. Слова KPUB-блоку, які фабрика емітує для золотого ключа, розпаковуються в той
 *      самий ключ, і ним перевіряється Ruby-печатка (шов FW.30 BE-слів).
 *
 * Build: make -C firmware/test ota_seal
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <openssl/evp.h>
#include "../common/ota_seal.h"

static int tests_passed = 0;
static int tests_failed = 0;

#define TEST(name) static void name(void)
#define RUN(name) do { \
    int _before = tests_failed; \
    printf("  %-62s", #name); \
    name(); \
    if (tests_failed == _before) { printf(" ✅\n"); tests_passed++; } \
} while(0)

#define ASSERT_EQ(a, b) do { \
    long long _a = (long long)(a), _b = (long long)(b); \
    if (_a != _b) { \
        printf(" ❌ FAIL (line %d: got %lld, expected %lld)\n", __LINE__, _a, _b); \
        tests_failed++; return; \
    } \
} while(0)
#define ASSERT_TRUE(expr)  ASSERT_EQ(!!(expr), 1)
#define ASSERT_FALSE(expr) ASSERT_EQ(!!(expr), 0)

/* Золотий вектор: master "silken-fw23-golden-master-key", cluster "cluster-golden-1"
 * → seed = HKDF-SHA256(master, "cluster:cluster-golden-1", "silken-ota-ed25519-v1"),
 * повідомлення = тіло ‖ version 42 BE ‖ total 3 BE, підпис — гем ed25519 (Ruby). */
static const uint8_t GOLDEN_PUB[32] = {
    0x90, 0xB7, 0xDB, 0xB7, 0x47, 0x63, 0x0A, 0x9E,
    0x2D, 0xDE, 0x9A, 0xE8, 0x6C, 0x2B, 0x28, 0xB3,
    0xF4, 0x34, 0x21, 0xC5, 0x53, 0xC6, 0x19, 0x6A,
    0xB5, 0xF6, 0x1F, 0xD6, 0x73, 0x2F, 0xC1, 0x46
};
static const uint8_t GOLDEN_BODY[22] = {
    0x52, 0x49, 0x54, 0x45, 0x03, 0x00, 0x00, 0x00,
    0xA0, 0xA1, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6, 0xA7,
    0xA8, 0xA9, 0xAA, 0xAB, 0xAC, 0xAD
};
static const uint8_t GOLDEN_SIG[64] = {
    0x4D, 0x0C, 0x90, 0x2D, 0x73, 0x5A, 0x2A, 0x11,
    0x45, 0xED, 0x5B, 0xE8, 0x35, 0x2C, 0x08, 0x26,
    0x49, 0xB2, 0x84, 0x70, 0x2D, 0xEF, 0x22, 0x31,
    0x0C, 0x55, 0xB5, 0x3F, 0xDF, 0x05, 0x5C, 0x7F,
    0xF9, 0x67, 0xB4, 0xE5, 0xDE, 0x87, 0xE1, 0x89,
    0x06, 0x30, 0xBD, 0x25, 0xA0, 0x7C, 0x97, 0xCF,
    0x4E, 0x06, 0x82, 0xE3, 0x3F, 0x10, 0x9A, 0xEA,
    0xF4, 0xB5, 0x4C, 0x96, 0xC1, 0x50, 0x67, 0x0A
};
static const uint8_t GOLDEN_SUFFIX[OTA_SEAL_SUFFIX_BYTES] = { 0x00, 0x00, 0x00, 0x2A, 0x00, 0x03 };

/* Рівно ці слова емітує FactoryFlashing::CommandBuilder для GOLDEN_PUB (пін —
 * spec/services/factory_flashing/command_builder_spec.rb: «KPUB words of the golden key»). */
static const uint32_t GOLDEN_PUB_WORDS[OTA_SEAL_PUBKEY_WORDS] = {
    0x90B7DBB7u, 0x47630A9Eu, 0x2DDE9AE8u, 0x6C2B28B3u,
    0xF43421C5u, 0x53C6196Au, 0xB5F61FD6u, 0x732FC146u
};

/* Детермінований PRNG — щоб прогони відтворювались побайтово. */
static uint32_t rng_state = 0x5EA1ED23u;
static uint8_t rnd8(void)
{
    rng_state ^= rng_state << 13; rng_state ^= rng_state >> 17; rng_state ^= rng_state << 5;
    return (uint8_t)rng_state;
}

static int openssl_pub(const uint8_t seed[32], uint8_t pub[32])
{
    EVP_PKEY *key = EVP_PKEY_new_raw_private_key(EVP_PKEY_ED25519, NULL, seed, 32);
    size_t len = 32;
    int ok = key && EVP_PKEY_get_raw_public_key(key, pub, &len) == 1 && len == 32;
    EVP_PKEY_free(key);
    return ok;
}

static int openssl_sign(const uint8_t seed[32], const uint8_t *msg, size_t msg_len, uint8_t sig[64])
{
    EVP_PKEY *key = EVP_PKEY_new_raw_private_key(EVP_PKEY_ED25519, NULL, seed, 32);
    EVP_MD_CTX *ctx = EVP_MD_CTX_new();
    size_t len = 64;
    int ok = key && ctx && EVP_DigestSignInit(ctx, NULL, NULL, NULL, key) == 1 &&
             EVP_DigestSign(ctx, sig, &len, msg, msg_len) == 1 && len == 64;
    EVP_MD_CTX_free(ctx);
    EVP_PKEY_free(key);
    return ok;
}

static int openssl_verify(const uint8_t pub[32], const uint8_t *msg, size_t msg_len, const uint8_t sig[64])
{
    EVP_PKEY *key = EVP_PKEY_new_raw_public_key(EVP_PKEY_ED25519, NULL, pub, 32);
    EVP_MD_CTX *ctx = EVP_MD_CTX_new();
    int ok = key && ctx && EVP_DigestVerifyInit(ctx, NULL, NULL, NULL, key) == 1 &&
             EVP_DigestVerify(ctx, sig, 64, msg, msg_len) == 1;
    EVP_MD_CTX_free(ctx);
    EVP_PKEY_free(key);
    return ok;
}

static size_t golden_message(uint8_t out[sizeof(GOLDEN_BODY) + OTA_SEAL_SUFFIX_BYTES])
{
    memcpy(out, GOLDEN_BODY, sizeof(GOLDEN_BODY));
    memcpy(out + sizeof(GOLDEN_BODY), GOLDEN_SUFFIX, OTA_SEAL_SUFFIX_BYTES);
    return sizeof(GOLDEN_BODY) + OTA_SEAL_SUFFIX_BYTES;
}

/* 1. Ruby-печатка: три перевіряльники погоджуються. */
TEST(test_golden_ruby_seal_verifies_in_firmware_monocypher_and_openssl) {
    uint8_t msg[sizeof(GOLDEN_BODY) + OTA_SEAL_SUFFIX_BYTES];
    size_t len = golden_message(msg);
    ASSERT_TRUE(Ota_Seal_Verify(GOLDEN_PUB, GOLDEN_SIG, GOLDEN_BODY, sizeof(GOLDEN_BODY),
                                GOLDEN_SUFFIX, OTA_SEAL_SUFFIX_BYTES));
    ASSERT_EQ(crypto_ed25519_check(GOLDEN_SIG, GOLDEN_PUB, msg, len), 0);
    ASSERT_TRUE(openssl_verify(GOLDEN_PUB, msg, len, GOLDEN_SIG));
}

/* Кожна складова підписаного — тіло, версія, кількість чанків, підпис, ключ — несуча. */
TEST(test_golden_seal_breaks_on_any_flipped_input) {
    uint8_t body[sizeof(GOLDEN_BODY)], suffix[OTA_SEAL_SUFFIX_BYTES], sig[64], pub[32];
    memcpy(body, GOLDEN_BODY, sizeof(body)); body[17] ^= 0x01;
    ASSERT_FALSE(Ota_Seal_Verify(GOLDEN_PUB, GOLDEN_SIG, body, sizeof(body), GOLDEN_SUFFIX, sizeof(suffix)));
    memcpy(suffix, GOLDEN_SUFFIX, sizeof(suffix)); suffix[3] = 0x2B;           /* version 43 */
    ASSERT_FALSE(Ota_Seal_Verify(GOLDEN_PUB, GOLDEN_SIG, GOLDEN_BODY, sizeof(GOLDEN_BODY), suffix, sizeof(suffix)));
    memcpy(suffix, GOLDEN_SUFFIX, sizeof(suffix)); suffix[5] = 0x02;           /* total 2 */
    ASSERT_FALSE(Ota_Seal_Verify(GOLDEN_PUB, GOLDEN_SIG, GOLDEN_BODY, sizeof(GOLDEN_BODY), suffix, sizeof(suffix)));
    for (int i = 0; i < 64; i += 21) {                                          /* R і S */
        memcpy(sig, GOLDEN_SIG, 64); sig[i] ^= 0x80;
        ASSERT_FALSE(Ota_Seal_Verify(GOLDEN_PUB, sig, GOLDEN_BODY, sizeof(GOLDEN_BODY), GOLDEN_SUFFIX, sizeof(suffix)));
    }
    memcpy(pub, GOLDEN_PUB, 32); pub[0] ^= 0x01;
    ASSERT_FALSE(Ota_Seal_Verify(pub, GOLDEN_SIG, GOLDEN_BODY, sizeof(GOLDEN_BODY), GOLDEN_SUFFIX, sizeof(suffix)));
}

/* 2. OpenSSL і Monocypher виводять той самий публічний ключ із seed і приймають
 * підписи одне одного (той самий RFC 8032, дві незалежні реалізації). */
TEST(test_openssl_and_monocypher_agree_on_keys_and_signatures) {
    for (int round = 0; round < 16; round++) {
        uint8_t seed[32], seed_copy[32], sk[64], pk_mono[32], pk_ossl[32], msg[200], sig_mono[64], sig_ossl[64];
        for (int i = 0; i < 32; i++) seed[i] = rnd8();
        size_t len = (size_t)(rnd8() % 200);
        for (size_t i = 0; i < len; i++) msg[i] = rnd8();
        memcpy(seed_copy, seed, 32);
        crypto_ed25519_key_pair(sk, pk_mono, seed_copy);                       /* Monocypher витирає копію */
        ASSERT_TRUE(openssl_pub(seed, pk_ossl));
        ASSERT_EQ(memcmp(pk_mono, pk_ossl, 32), 0);

        ASSERT_TRUE(openssl_sign(seed, msg, len, sig_ossl));
        crypto_ed25519_sign(sig_mono, sk, msg, len);
        ASSERT_EQ(memcmp(sig_mono, sig_ossl, 64), 0);                          /* детермінізм обабіч */

        size_t cut = len ? (size_t)(rnd8() % (len + 1)) : 0;
        ASSERT_TRUE(Ota_Seal_Verify(pk_ossl, sig_ossl, msg, cut, msg + cut, len - cut));
        ASSERT_TRUE(openssl_verify(pk_mono, msg, len, sig_mono));
    }
}

/* 3. Стрімінг ≡ одноразова перевірка на склеєному — і для справжніх, і для зіпсованих. */
TEST(test_streamed_verify_equals_crypto_ed25519_check) {
    uint8_t sk[64], pk[32], seed[32];
    for (int i = 0; i < 32; i++) seed[i] = (uint8_t)(0x3C ^ i);
    crypto_ed25519_key_pair(sk, pk, seed);
    for (int round = 0; round < 64; round++) {
        uint8_t msg[300], sig[64];
        size_t len = (size_t)(rnd8() % 255) + 1;
        for (size_t i = 0; i < len; i++) msg[i] = rnd8();
        crypto_ed25519_sign(sig, sk, msg, len);
        if (round % 3 == 1) sig[rnd8() % 64] ^= (uint8_t)(1u << (rnd8() % 8));  /* зіпсований */
        if (round % 3 == 2) msg[rnd8() % len] ^= 0x10;
        int oneshot = crypto_ed25519_check(sig, pk, msg, len) == 0;
        for (size_t cut = 0; cut <= len; cut += 1 + len / 7) {
            ASSERT_EQ(Ota_Seal_Verify(pk, sig, msg, cut, msg + cut, len - cut), oneshot);
        }
        if (round % 3 == 0) ASSERT_TRUE(oneshot);
    }
}

/* 4. Шов фабрика → Flash → прошивка: слова фабрики дають той самий ключ, і ним Ruby-печатка
 * перевіряється; наївний memcpy (LE-хост, як і Cortex-M4) дав би інший ключ і REJECT. */
TEST(test_factory_kpub_words_unpack_to_the_golden_key) {
    uint8_t pk[OTA_SEAL_PUBKEY_BYTES];
    ASSERT_EQ(Ota_Seal_Pubkey_From_Words(GOLDEN_PUB_WORDS, pk), 1);
    ASSERT_EQ(memcmp(pk, GOLDEN_PUB, sizeof(pk)), 0);
    ASSERT_TRUE(Ota_Seal_Verify(pk, GOLDEN_SIG, GOLDEN_BODY, sizeof(GOLDEN_BODY),
                                GOLDEN_SUFFIX, OTA_SEAL_SUFFIX_BYTES));

    const uint16_t probe = 1;
    if (*(const uint8_t *)&probe == 1) {          /* LE-хост — та сама пастка, що на M4 */
        uint8_t naive[OTA_SEAL_PUBKEY_BYTES];
        memcpy(naive, GOLDEN_PUB_WORDS, sizeof(naive));
        ASSERT_FALSE(memcmp(naive, GOLDEN_PUB, sizeof(naive)) == 0);
        ASSERT_FALSE(Ota_Seal_Verify(naive, GOLDEN_SIG, GOLDEN_BODY, sizeof(GOLDEN_BODY),
                                     GOLDEN_SUFFIX, OTA_SEAL_SUFFIX_BYTES));
    }

    static const uint32_t erased_key[OTA_SEAL_PUBKEY_WORDS] = { 0 };
    ASSERT_EQ(Ota_Seal_Pubkey_From_Words(erased_key, pk), 0);
}

int main(void)
{
    printf("\n═══ FW.23 OTA seal parity (Ed25519) ═══\n");
    RUN(test_golden_ruby_seal_verifies_in_firmware_monocypher_and_openssl);
    RUN(test_golden_seal_breaks_on_any_flipped_input);
    RUN(test_openssl_and_monocypher_agree_on_keys_and_signatures);
    RUN(test_streamed_verify_equals_crypto_ed25519_check);
    RUN(test_factory_kpub_words_unpack_to_the_golden_key);
    printf("\n═══ Results: %d passed, %d failed ═══\n", tests_passed, tests_failed);
    return tests_failed ? 1 : 0;
}
