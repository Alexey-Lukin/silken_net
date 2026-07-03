/*
 * test_queen_attest.c — [L1 QATT] host-тести Queen-attestation батч-конверта.
 *
 * Три шари:
 *   1. Layout-інваріанти common/queen_attest.h (residue, зсуви, префікс).
 *   2. Crypto-parity: Monocypher (прошивка) ↔ OpenSSL EVP (незалежна
 *      реалізація) — той самий seed → той самий pubkey; детермінований
 *      Ed25519 → байт-у-байт той самий підпис; крос-верифікація.
 *   3. End-to-end конверт: збірка РІВНО як у Flush_Cache_To_Rails →
 *      розбір РІВНО як у бекенда (UnpackTelemetryWorker) → verify.
 *      Golden-KAT константи дзеркаляться у RSpec
 *      (spec/workers/unpack_telemetry_worker_attest_spec.rb) — третя
 *      реалізація (ruby `ed25519` gem) мусить дати ту саму відповідь.
 *
 * Build: make -C firmware/test attest
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#include "../common/queen_attest.h"
#include "monocypher.h"
#include "monocypher-ed25519.h"

#include <openssl/evp.h>

/* ════════════════════════════════════════════════════════════════════
 * TEST FRAMEWORK (house pattern — test_queen_logic.c)
 * ════════════════════════════════════════════════════════════════════ */
static int tests_passed = 0;
static int tests_failed = 0;

#define TEST(name) static void name(void)
#define RUN(name) do { \
    printf("  %-58s", #name); \
    name(); \
    printf(" ✅\n"); \
    tests_passed++; \
} while(0)

#define ASSERT_EQ(a, b) do { \
    long long _a = (long long)(a), _b = (long long)(b); \
    if (_a != _b) { \
        printf(" ❌ FAIL (line %d: got %lld, expected %lld)\n", __LINE__, _a, _b); \
        tests_failed++; return; \
    } \
} while(0)

#define ASSERT_TRUE(expr) ASSERT_EQ(!!(expr), 1)
#define ASSERT_FALSE(expr) ASSERT_EQ(!!(expr), 0)

#define ASSERT_MEMEQ(a, b, n) do { \
    if (memcmp((a), (b), (n)) != 0) { \
        printf(" ❌ FAIL (line %d: %zu-byte buffers differ)\n", __LINE__, (size_t)(n)); \
        tests_failed++; return; \
    } \
} while(0)

/* ════════════════════════════════════════════════════════════════════
 * GOLDEN-KAT входи — заморожені; ті САМІ значення живуть у RSpec-дзеркалі.
 * Кожна сторона НЕЗАЛЕЖНО деривує підпис зі входів і порівнює з expected —
 * дрейф будь-якої реалізації валить її власний тест.
 * ════════════════════════════════════════════════════════════════════ */
static const uint8_t GOLDEN_SEED[32] = {
    0x53, 0x49, 0x4C, 0x4B, 0x45, 0x4E, 0x2D, 0x4E,  /* "SILKEN-N" */
    0x45, 0x54, 0x2D, 0x4C, 0x31, 0x2D, 0x51, 0x41,  /* "ET-L1-QA" */
    0x54, 0x54, 0x2D, 0x47, 0x4F, 0x4C, 0x44, 0x45,  /* "TT-GOLDE" */
    0x4E, 0x2D, 0x53, 0x45, 0x45, 0x44, 0x21, 0x21   /* "N-SEED!!" */
};
static const char     GOLDEN_UID[]   = "SNET-Q-A1B2C3D4";
static const uint32_t GOLDEN_TS      = 1750000000u;
static const uint32_t GOLDEN_SEQ     = 7u;
/* [ARCH.54] health-блок v2 (8 байт у header) — заморожені входи KAT */
static const uint32_t GOLDEN_UPTIME  = 5310u;   /* хвилин ≈ 3.7 доби */
static const uint8_t  GOLDEN_CIFO    = 42u;
static const uint8_t  GOLDEN_DROPS   = 3u;
static const uint8_t  GOLDEN_COAPF   = 1u;
static const uint8_t  GOLDEN_CSQ     = 17u;
static const uint8_t  GOLDEN_FLAGS   = 0x00u;
static const uint8_t  GOLDEN_IV[16]  = {
    0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77,
    0x88, 0x99, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF
};
/* 2 AES-блоки «шифротексту» (для конверта це непрозорі байти) */
static const uint8_t  GOLDEN_CT[32]  = {
    0xDE, 0xAD, 0xBE, 0xEF, 0x01, 0x02, 0x03, 0x04,
    0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C,
    0xC0, 0xFF, 0xEE, 0x00, 0x10, 0x20, 0x30, 0x40,
    0x50, 0x60, 0x70, 0x80, 0x90, 0xA0, 0xB0, 0xC0
};

/* Заморожений KAT (згенеровано Monocypher, звірено OpenSSL; RSpec-дзеркало
 * деривує ту саму пару з тих самих входів через ruby `ed25519`):
 *   GOLDEN_PUB = 963058b4a0e2686c7dfcd823bd59643f941aebffbba13336ed2d41d2fd22d2b0 */
static const char GOLDEN_SIG_HEX[129] =
    "c7b5e07db501233eed0a43d10a1988f4ba0b0a3a59ac2d39cf0c542b7be2d266"
    "82bf0a1d31533b3405ae2f691648308e7ddbfd0e507934ce235161f572c2b40f";

/* ── Helpers ────────────────────────────────────────────────────────── */

static int hex_decode(const char *hex, uint8_t *out, size_t out_len)
{
    for (size_t i = 0; i < out_len; i++) {
        unsigned v;
        if (sscanf(hex + 2 * i, "%2x", &v) != 1) return 0;
        out[i] = (uint8_t)v;
    }
    return 1;
}

/* OpenSSL Ed25519 detached sign (незалежна реалізація для parity) */
static int openssl_ed25519_sign(uint8_t sig[64], const uint8_t seed[32],
                                const uint8_t *msg, size_t msg_len)
{
    EVP_PKEY *pkey = EVP_PKEY_new_raw_private_key(EVP_PKEY_ED25519, NULL, seed, 32);
    if (!pkey) return 0;
    EVP_MD_CTX *ctx = EVP_MD_CTX_new();
    size_t sig_len = 64;
    int ok = ctx
          && EVP_DigestSignInit(ctx, NULL, NULL, NULL, pkey) == 1
          && EVP_DigestSign(ctx, sig, &sig_len, msg, msg_len) == 1
          && sig_len == 64;
    EVP_MD_CTX_free(ctx);
    EVP_PKEY_free(pkey);
    return ok;
}

static int openssl_ed25519_verify(const uint8_t sig[64], const uint8_t pub[32],
                                  const uint8_t *msg, size_t msg_len)
{
    EVP_PKEY *pkey = EVP_PKEY_new_raw_public_key(EVP_PKEY_ED25519, NULL, pub, 32);
    if (!pkey) return 0;
    EVP_MD_CTX *ctx = EVP_MD_CTX_new();
    int ok = ctx
          && EVP_DigestVerifyInit(ctx, NULL, NULL, NULL, pkey) == 1
          && EVP_DigestVerify(ctx, sig, 64, msg, msg_len) == 1;
    EVP_MD_CTX_free(ctx);
    EVP_PKEY_free(pkey);
    return ok;
}

static int openssl_ed25519_pub(uint8_t pub[32], const uint8_t seed[32])
{
    EVP_PKEY *pkey = EVP_PKEY_new_raw_private_key(EVP_PKEY_ED25519, NULL, seed, 32);
    if (!pkey) return 0;
    size_t pub_len = 32;
    int ok = EVP_PKEY_get_raw_public_key(pkey, pub, &pub_len) == 1 && pub_len == 32;
    EVP_PKEY_free(pkey);
    return ok;
}

/* Збірка конверта РІВНО як Flush_Cache_To_Rails: спільний буфер,
 * право-вирівняний префікс, підпис хвостом. Повертає payload-вікно. */
static uint16_t build_signed_payload(uint8_t *buf /* QATT_BUFFER_SIZE */,
                                     const uint8_t seed[32], const char *uid,
                                     uint32_t ts, uint32_t seq,
                                     const uint8_t iv[16],
                                     const uint8_t *ct, uint16_t ct_len,
                                     const uint8_t **payload_out)
{
    uint8_t secret[64], pub[32], seed_copy[32];
    memcpy(seed_copy, seed, 32);
    crypto_ed25519_key_pair(secret, pub, seed_copy);  /* seed_copy wiped */

    memcpy(buf + QATT_IV_OFFSET, iv, QATT_IV_LEN);
    memcpy(buf + QATT_CT_OFFSET, ct, ct_len);
    Qatt_Write_Header(buf + QATT_HDR_OFFSET, ts, seq,
                      GOLDEN_UPTIME, GOLDEN_CIFO, GOLDEN_DROPS,
                      GOLDEN_COAPF, GOLDEN_CSQ, GOLDEN_FLAGS);

    uint16_t prefix_len = Qatt_Compose_Prefix(buf, QATT_HDR_OFFSET, uid);
    if (prefix_len == 0u) return 0u;

    const uint8_t *msg = buf + QATT_HDR_OFFSET - prefix_len;
    size_t msg_len = (size_t)prefix_len + QATT_HEADER_LEN + QATT_IV_LEN + ct_len;
    crypto_ed25519_sign(buf + QATT_CT_OFFSET + ct_len, secret, msg, msg_len);

    *payload_out = buf + QATT_HDR_OFFSET;
    return (uint16_t)(QATT_HEADER_LEN + QATT_IV_LEN + ct_len + QATT_SIG_LEN);
}

/* ════════════════════════════════════════════════════════════════════
 * 1. LAYOUT-ІНВАРІАНТИ
 * ════════════════════════════════════════════════════════════════════ */

TEST(test_layout_residue_discriminates_signed_from_legacy)
{
    /* Підписаний хвіст (header+IV+sig) ≡ 1 (mod 16); legacy ≡ 0 — їхні
     * довжини НІКОЛИ не перетинаються, скільки б ct-блоків не їхало.
     * [ARCH.54] ct=0 (empty-flush heartbeat) — теж legальний signed. */
    ASSERT_EQ(QATT_RESIDUE, 1u);
    for (uint16_t blocks = 0; blocks <= 4; blocks++) {
        uint16_t ct = (uint16_t)(blocks * 16u);
        ASSERT_EQ((QATT_HEADER_LEN + QATT_IV_LEN + ct + QATT_SIG_LEN) % 16u, 1u);
        ASSERT_EQ((QATT_IV_LEN + ct) % 16u, 0u);
    }
}

TEST(test_layout_offsets_contiguous_and_aligned)
{
    ASSERT_EQ(QATT_HDR_OFFSET + QATT_HEADER_LEN, QATT_IV_OFFSET);
    ASSERT_EQ(QATT_IV_OFFSET + QATT_IV_LEN, QATT_CT_OFFSET);
    ASSERT_EQ(QATT_CT_OFFSET % 16u, 0u);         /* HAL_CRYP word-доступ */
    ASSERT_TRUE(QATT_HDR_OFFSET >= QATT_PREFIX_MAX);
}

TEST(test_header_packs_big_endian)
{
    uint8_t hdr[QATT_HEADER_LEN];
    Qatt_Write_Header(hdr, 0x01020304u, 0xAABBCCDDu,
                      0x00112233u /* > u24 → клемп */, 50u, 7u, 2u, 31u, 0x03u);
    ASSERT_EQ(hdr[0], QATT_VERSION_2);
    ASSERT_EQ(hdr[1], 0x01); ASSERT_EQ(hdr[2], 0x02);
    ASSERT_EQ(hdr[3], 0x03); ASSERT_EQ(hdr[4], 0x04);
    ASSERT_EQ(hdr[5], 0xAA); ASSERT_EQ(hdr[6], 0xBB);
    ASSERT_EQ(hdr[7], 0xCC); ASSERT_EQ(hdr[8], 0xDD);
    /* [ARCH.54] health: uptime u24 BE (клемп зі старшого байта), решта — 1:1 */
    ASSERT_EQ(hdr[9], 0x11); ASSERT_EQ(hdr[10], 0x22); ASSERT_EQ(hdr[11], 0x33);
    ASSERT_EQ(hdr[12], 50u); ASSERT_EQ(hdr[13], 7u);
    ASSERT_EQ(hdr[14], 2u);  ASSERT_EQ(hdr[15], 31u);
    ASSERT_EQ(hdr[16], 0x03u);
}

TEST(test_header_uptime_clamps_at_u24)
{
    uint8_t hdr[QATT_HEADER_LEN];
    Qatt_Write_Header(hdr, 0u, 0u, 0xFFFFFFFFu, 0u, 0u, 0u,
                      QATT_CSQ_NOT_READ, 0u);
    ASSERT_EQ(hdr[9], 0xFF); ASSERT_EQ(hdr[10], 0xFF); ASSERT_EQ(hdr[11], 0xFF);
    ASSERT_EQ(hdr[15], QATT_CSQ_NOT_READ);
}

TEST(test_prefix_right_aligned_with_len_byte)
{
    uint8_t area[QATT_HDR_OFFSET];
    memset(area, 0xEE, sizeof area);
    uint16_t plen = Qatt_Compose_Prefix(area, QATT_HDR_OFFSET, "SNET-Q-00FF00FF");
    ASSERT_EQ(plen, QATT_DOMAIN_TAG_LEN + 1u + 15u);

    const uint8_t *p = area + QATT_HDR_OFFSET - plen;
    ASSERT_MEMEQ(p, QATT_DOMAIN_TAG, QATT_DOMAIN_TAG_LEN);
    ASSERT_EQ(p[QATT_DOMAIN_TAG_LEN], 15u);
    ASSERT_MEMEQ(p + QATT_DOMAIN_TAG_LEN + 1u, "SNET-Q-00FF00FF", 15u);
    /* зона лівіше префікса недоторкана */
    ASSERT_EQ(area[0], 0xEE);
}

TEST(test_prefix_rejects_empty_and_oversized_uid)
{
    uint8_t area[QATT_HDR_OFFSET];
    ASSERT_EQ(Qatt_Compose_Prefix(area, QATT_HDR_OFFSET, ""), 0u);
    ASSERT_EQ(Qatt_Compose_Prefix(area, QATT_HDR_OFFSET, NULL), 0u);
    /* 32 символи — на 1 за межею QATT_UID_MAX */
    ASSERT_EQ(Qatt_Compose_Prefix(area, QATT_HDR_OFFSET,
                                  "0123456789ABCDEF0123456789ABCDEF"), 0u);
    /* рівно 31 — максимум, що влазить */
    ASSERT_EQ(Qatt_Compose_Prefix(area, QATT_HDR_OFFSET,
                                  "0123456789ABCDEF0123456789ABCDE"),
              QATT_DOMAIN_TAG_LEN + 1u + 31u);
}

/* ════════════════════════════════════════════════════════════════════
 * 2. CRYPTO-PARITY: Monocypher ↔ OpenSSL
 * ════════════════════════════════════════════════════════════════════ */

TEST(test_monocypher_pubkey_matches_openssl)
{
    uint8_t secret[64], pub_mc[32], pub_ssl[32], seed_copy[32];
    memcpy(seed_copy, GOLDEN_SEED, 32);
    crypto_ed25519_key_pair(secret, pub_mc, seed_copy);
    ASSERT_TRUE(openssl_ed25519_pub(pub_ssl, GOLDEN_SEED));
    ASSERT_MEMEQ(pub_mc, pub_ssl, 32);
}

TEST(test_monocypher_signature_byte_equals_openssl)
{
    /* Ed25519 детермінований (RFC 8032) → дві чесні реалізації дають
     * байт-у-байт той самий підпис. Це найсильніший parity-доказ. */
    static const uint8_t msg[] = "Forest speaks; the Queen attests.";
    uint8_t secret[64], pub[32], seed_copy[32];
    memcpy(seed_copy, GOLDEN_SEED, 32);
    crypto_ed25519_key_pair(secret, pub, seed_copy);

    uint8_t sig_mc[64], sig_ssl[64];
    crypto_ed25519_sign(sig_mc, secret, msg, sizeof msg - 1);
    ASSERT_TRUE(openssl_ed25519_sign(sig_ssl, GOLDEN_SEED, msg, sizeof msg - 1));
    ASSERT_MEMEQ(sig_mc, sig_ssl, 64);

    /* крос-верифікація + tamper-fail */
    ASSERT_TRUE(openssl_ed25519_verify(sig_mc, pub, msg, sizeof msg - 1));
    ASSERT_TRUE(crypto_ed25519_check(sig_ssl, pub, msg, sizeof msg - 1) == 0);
    uint8_t bad[64]; memcpy(bad, sig_mc, 64); bad[0] ^= 0x01;
    ASSERT_FALSE(openssl_ed25519_verify(bad, pub, msg, sizeof msg - 1));
}

/* ════════════════════════════════════════════════════════════════════
 * 3. END-TO-END КОНВЕРТ (firmware-збірка → backend-розбір)
 * ════════════════════════════════════════════════════════════════════ */

TEST(test_envelope_roundtrip_backend_view)
{
    static uint8_t buf[QATT_BUFFER_SIZE];
    const uint8_t *payload = NULL;
    uint16_t plen = build_signed_payload(buf, GOLDEN_SEED, GOLDEN_UID,
                                         GOLDEN_TS, GOLDEN_SEQ,
                                         GOLDEN_IV, GOLDEN_CT, sizeof GOLDEN_CT,
                                         &payload);
    ASSERT_TRUE(plen > 0u);
    ASSERT_EQ(plen % 16u, QATT_RESIDUE);   /* бекендів дискримінатор */

    /* Розбір РІВНО як UnpackTelemetryWorker: sig = хвіст, message =
     * tag‖uid_len‖uid‖payload-без-sig (uid бекенд знає з CoAP URI-Path). */
    const uint8_t *sig = payload + plen - QATT_SIG_LEN;
    size_t body_len = (size_t)plen - QATT_SIG_LEN;

    uint8_t msg[QATT_PREFIX_MAX + QATT_HEADER_LEN + QATT_IV_LEN + sizeof GOLDEN_CT];
    size_t uid_len = strlen(GOLDEN_UID);
    size_t off = 0;
    memcpy(msg + off, QATT_DOMAIN_TAG, QATT_DOMAIN_TAG_LEN); off += QATT_DOMAIN_TAG_LEN;
    msg[off++] = (uint8_t)uid_len;
    memcpy(msg + off, GOLDEN_UID, uid_len); off += uid_len;
    memcpy(msg + off, payload, body_len);   off += body_len;

    uint8_t pub[32];
    ASSERT_TRUE(openssl_ed25519_pub(pub, GOLDEN_SEED));
    ASSERT_TRUE(openssl_ed25519_verify(sig, pub, msg, off));

    /* header розпаковується назад у (ver, ts, seq, health) */
    ASSERT_EQ(payload[0], QATT_VERSION_2);
    uint32_t ts = ((uint32_t)payload[1] << 24) | ((uint32_t)payload[2] << 16)
                | ((uint32_t)payload[3] << 8)  |  (uint32_t)payload[4];
    uint32_t sq = ((uint32_t)payload[5] << 24) | ((uint32_t)payload[6] << 16)
                | ((uint32_t)payload[7] << 8)  |  (uint32_t)payload[8];
    ASSERT_EQ(ts, GOLDEN_TS);
    ASSERT_EQ(sq, GOLDEN_SEQ);
    uint32_t up = ((uint32_t)payload[9] << 16) | ((uint32_t)payload[10] << 8)
                |  (uint32_t)payload[11];
    ASSERT_EQ(up, GOLDEN_UPTIME);
    ASSERT_EQ(payload[12], GOLDEN_CIFO);
    ASSERT_EQ(payload[13], GOLDEN_DROPS);
    ASSERT_EQ(payload[14], GOLDEN_COAPF);
    ASSERT_EQ(payload[15], GOLDEN_CSQ);
    ASSERT_EQ(payload[16], GOLDEN_FLAGS);
    ASSERT_MEMEQ(payload + QATT_HEADER_LEN, GOLDEN_IV, QATT_IV_LEN);

    /* підпис НЕ переживає підміну UID (anti-splice між шлюзами) */
    uint8_t msg2[sizeof msg];
    memcpy(msg2, msg, off);
    msg2[QATT_DOMAIN_TAG_LEN + 1u] ^= 0x01;  /* перший байт UID */
    ASSERT_FALSE(openssl_ed25519_verify(sig, pub, msg2, off));
}

TEST(test_envelope_golden_kat_frozen)
{
    static uint8_t buf[QATT_BUFFER_SIZE];
    const uint8_t *payload = NULL;
    uint16_t plen = build_signed_payload(buf, GOLDEN_SEED, GOLDEN_UID,
                                         GOLDEN_TS, GOLDEN_SEQ,
                                         GOLDEN_IV, GOLDEN_CT, sizeof GOLDEN_CT,
                                         &payload);
    ASSERT_TRUE(plen > 0u);
    const uint8_t *sig = payload + plen - QATT_SIG_LEN;

    uint8_t expected[64];
    ASSERT_TRUE(hex_decode(GOLDEN_SIG_HEX, expected, 64));
    ASSERT_MEMEQ(sig, expected, 64);
}

/* ════════════════════════════════════════════════════════════════════ */

int main(void)
{
    printf("\n[L1 QATT] Queen-attestation envelope — host tests\n");
    printf("══════════════════════════════════════════════════════════════\n");

    printf("\n— Layout —\n");
    RUN(test_layout_residue_discriminates_signed_from_legacy);
    RUN(test_layout_offsets_contiguous_and_aligned);
    RUN(test_header_packs_big_endian);
    RUN(test_header_uptime_clamps_at_u24);
    RUN(test_prefix_right_aligned_with_len_byte);
    RUN(test_prefix_rejects_empty_and_oversized_uid);

    printf("\n— Crypto parity (Monocypher ↔ OpenSSL) —\n");
    RUN(test_monocypher_pubkey_matches_openssl);
    RUN(test_monocypher_signature_byte_equals_openssl);

    printf("\n— End-to-end envelope —\n");
    RUN(test_envelope_roundtrip_backend_view);
    RUN(test_envelope_golden_kat_frozen);

    printf("\n══════════════════════════════════════════════════════════════\n");
    printf("Підсумок: %d ✅ / %d ❌\n\n", tests_passed, tests_failed);
    return tests_failed == 0 ? 0 : 1;
}
