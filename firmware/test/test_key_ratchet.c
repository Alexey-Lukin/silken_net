// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * test_key_ratchet.c — [FW.17] Hash-Ratchet ротація LoRa-ключа (host).
 *
 * Golden-KAT (K0=000102..0F, DID=0xDEADBEEF) заморожено freeze-contract'ом
 * з бекендом: ті самі вектори звіряє spec/lib/cryptography/key_ratchet_spec.rb
 * (OpenSSL::HMAC) — byte-parity pure-C ↔ Ruby. Wire-кадр 0x9E дзеркалиться
 * проти OtaPackagerService.build_rotate_key_block.
 *
 * Build: make -C firmware/test key_ratchet
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#include "../common/key_ratchet.h"

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

#define ASSERT_KEY_EQ(key, hex) do { \
    char _got[2 * KEY_RATCHET_KEY_LEN + 1]; \
    for (unsigned _i = 0; _i < KEY_RATCHET_KEY_LEN; _i++) \
        sprintf(_got + 2 * _i, "%02X", (key)[_i]); \
    if (strcmp(_got, (hex)) != 0) { \
        printf(" ❌ FAIL (line %d: got %s, expected %s)\n", __LINE__, _got, (hex)); \
        tests_failed++; return; \
    } \
} while(0)

/* Golden-вхід: K0 = 00 01 02 .. 0F, DID = 0xDEADBEEF. */
#define KAT_DID 0xDEADBEEFu
static void kat_k0(uint8_t key[KEY_RATCHET_KEY_LEN])
{
    for (uint8_t i = 0; i < KEY_RATCHET_KEY_LEN; i++) key[i] = i;
}

/* ════════════════════════════════════════════════════════════════════
 * 1. KAT-ланцюг (freeze-contract з Ruby)
 * ════════════════════════════════════════════════════════════════════ */
TEST(test_kat_chain_k1_k2_k3) {
    uint8_t key[KEY_RATCHET_KEY_LEN];
    kat_k0(key);
    Key_Ratchet_Next(key, KAT_DID);
    ASSERT_KEY_EQ(key, "C2A8861DEF01E2A944D3CD989A7CF117");
    Key_Ratchet_Next(key, KAT_DID);
    ASSERT_KEY_EQ(key, "4E1E7355E593D034E7D800D0B9843506");
    Key_Ratchet_Next(key, KAT_DID);
    ASSERT_KEY_EQ(key, "C7593AA70E31334ABB2BA45DC79B153B");
}

TEST(test_kat_did_separates_chains) {
    /* Той самий K0, інший DID → інший ланцюг (Context у SP 800-108 KDF). */
    uint8_t a[KEY_RATCHET_KEY_LEN], b[KEY_RATCHET_KEY_LEN];
    kat_k0(a); kat_k0(b);
    Key_Ratchet_Next(a, KAT_DID);
    Key_Ratchet_Next(b, 0xCAFEF00Du);
    ASSERT_TRUE(memcmp(a, b, KEY_RATCHET_KEY_LEN) != 0);
}

/* ════════════════════════════════════════════════════════════════════
 * 2. Версійна дисципліна (rollback/replay/runaway)
 * ════════════════════════════════════════════════════════════════════ */
TEST(test_steps_forward_only) {
    ASSERT_EQ(Key_Ratchet_Steps(3, 4), 1);
    ASSERT_EQ(Key_Ratchet_Steps(3, 3), 0);  /* replay тієї ж версії */
    ASSERT_EQ(Key_Ratchet_Steps(3, 2), 0);  /* rollback */
    ASSERT_EQ(Key_Ratchet_Steps(0, 8), 8);  /* рівно стеля */
    ASSERT_EQ(Key_Ratchet_Steps(0, 9), 0);  /* понад стелю — відмова */
}

TEST(test_advance_applies_steps_and_version) {
    uint8_t key[KEY_RATCHET_KEY_LEN];
    uint16_t version = 0;
    kat_k0(key);
    ASSERT_TRUE(Key_Ratchet_Advance(key, &version, 3, KAT_DID));
    ASSERT_EQ(version, 3);
    ASSERT_KEY_EQ(key, "C7593AA70E31334ABB2BA45DC79B153B"); /* = K3 */
}

TEST(test_advance_reject_leaves_state_untouched) {
    uint8_t key[KEY_RATCHET_KEY_LEN];
    uint16_t version = 5;
    kat_k0(key);
    ASSERT_FALSE(Key_Ratchet_Advance(key, &version, 5, KAT_DID));   /* replay */
    ASSERT_FALSE(Key_Ratchet_Advance(key, &version, 2, KAT_DID));   /* rollback */
    ASSERT_FALSE(Key_Ratchet_Advance(key, &version, 100, KAT_DID)); /* runaway */
    ASSERT_EQ(version, 5);
    uint8_t k0[KEY_RATCHET_KEY_LEN];
    kat_k0(k0);
    ASSERT_EQ(memcmp(key, k0, KEY_RATCHET_KEY_LEN), 0);
}

TEST(test_boot_rederive_equals_incremental) {
    /* Boot-модель: K_current = ratchet^v(K0) мусить збігатися з
     * інкрементальним шляхом через довільні Advance-кроки. */
    uint8_t boot[KEY_RATCHET_KEY_LEN], incr[KEY_RATCHET_KEY_LEN];
    uint16_t version = 0;
    kat_k0(boot); kat_k0(incr);
    ASSERT_TRUE(Key_Ratchet_Advance(incr, &version, 2, KAT_DID));
    ASSERT_TRUE(Key_Ratchet_Advance(incr, &version, 6, KAT_DID));
    for (int i = 0; i < 6; i++) Key_Ratchet_Next(boot, KAT_DID);
    ASSERT_EQ(memcmp(boot, incr, KEY_RATCHET_KEY_LEN), 0);
}

TEST(test_apply_zero_is_identity_and_matches_kat) {
    /* Boot-restore: Apply(0) = K0 без змін; Apply(3) = KAT K3 (без стелі
     * MAX_JUMP — власний персистнутий стан, не ефірна команда). */
    uint8_t key[KEY_RATCHET_KEY_LEN], k0[KEY_RATCHET_KEY_LEN];
    kat_k0(key); kat_k0(k0);
    Key_Ratchet_Apply(key, 0, KAT_DID);
    ASSERT_EQ(memcmp(key, k0, KEY_RATCHET_KEY_LEN), 0);
    Key_Ratchet_Apply(key, 3, KAT_DID);
    ASSERT_KEY_EQ(key, "C7593AA70E31334ABB2BA45DC79B153B");
}

TEST(test_apply_exceeds_max_jump_ceiling) {
    /* 12 > MAX_JUMP=8: boot-катчап навмисно не обмежений стелею. */
    uint8_t boot[KEY_RATCHET_KEY_LEN], incr[KEY_RATCHET_KEY_LEN];
    kat_k0(boot); kat_k0(incr);
    Key_Ratchet_Apply(boot, 12, KAT_DID);
    for (int i = 0; i < 12; i++) Key_Ratchet_Next(incr, KAT_DID);
    ASSERT_EQ(memcmp(boot, incr, KEY_RATCHET_KEY_LEN), 0);
}

TEST(test_words_bytes_roundtrip_be_convention) {
    /* CRYP-міст: перший байт ключа = старший байт слова (конвенція -w32 /
     * Load_AES_Key). Roundtrip бітово-чистий. */
    uint8_t key[KEY_RATCHET_KEY_LEN], back[KEY_RATCHET_KEY_LEN];
    uint32_t words[4];
    kat_k0(key);
    Key_Ratchet_Bytes_To_Words(key, words);
    ASSERT_EQ(words[0], 0x00010203u);
    ASSERT_EQ(words[3], 0x0C0D0E0Fu);
    Key_Ratchet_Words_To_Bytes(words, back);
    ASSERT_EQ(memcmp(key, back, KEY_RATCHET_KEY_LEN), 0);
}

/* ════════════════════════════════════════════════════════════════════
 * 3. Wire-кадр 0x9E (дзеркало OtaPackagerService.build_rotate_key_block)
 * ════════════════════════════════════════════════════════════════════ */
TEST(test_parse_golden_frame) {
    /* Freeze-contract hex: 9E 0400 0300 5C48 (target_version = 3). */
    const uint8_t frame[] = { 0x9E, 0x04, 0x00, 0x03, 0x00, 0x5C, 0x48 };
    uint16_t target = 0;
    ASSERT_TRUE(Key_Ratchet_Parse_Cmd(frame, sizeof frame, &target));
    ASSERT_EQ(target, 3);
}

TEST(test_parse_rejects_garbage) {
    uint8_t frame[] = { 0x9E, 0x04, 0x00, 0x03, 0x00, 0x5C, 0x48 };
    uint16_t target;
    ASSERT_FALSE(Key_Ratchet_Parse_Cmd(frame, 6, &target));   /* куций */
    frame[0] = 0x9A;
    ASSERT_FALSE(Key_Ratchet_Parse_Cmd(frame, 7, &target));   /* чужий маркер */
    frame[0] = 0x9E; frame[1] = 0x05;
    ASSERT_FALSE(Key_Ratchet_Parse_Cmd(frame, 7, &target));   /* битий len */
    frame[1] = 0x04; frame[3] = 0x04;
    ASSERT_FALSE(Key_Ratchet_Parse_Cmd(frame, 7, &target));   /* битий CRC */
}

TEST(test_parse_then_advance_roundtrip) {
    /* Повний шлях кадр → парсер → ratchet: версія 0 → 3, ключ = K3. */
    const uint8_t frame[] = { 0x9E, 0x04, 0x00, 0x03, 0x00, 0x5C, 0x48 };
    uint8_t key[KEY_RATCHET_KEY_LEN];
    uint16_t version = 0, target = 0;
    kat_k0(key);
    ASSERT_TRUE(Key_Ratchet_Parse_Cmd(frame, sizeof frame, &target));
    ASSERT_TRUE(Key_Ratchet_Advance(key, &version, target, KAT_DID));
    ASSERT_KEY_EQ(key, "C7593AA70E31334ABB2BA45DC79B153B");
}

/* ════════════════════════════════════════════════════════════════════ */
int main(void)
{
    printf("════════════════════════════════════════════════════════════════════\n");
    printf("  [FW.17] Hash-Ratchet ротація LoRa-ключа — host KAT + wire\n");
    printf("════════════════════════════════════════════════════════════════════\n");

    printf("\n— KAT-ланцюг (parity з Ruby) —\n");
    RUN(test_kat_chain_k1_k2_k3);
    RUN(test_kat_did_separates_chains);

    printf("\n— Версійна дисципліна —\n");
    RUN(test_steps_forward_only);
    RUN(test_advance_applies_steps_and_version);
    RUN(test_advance_reject_leaves_state_untouched);
    RUN(test_boot_rederive_equals_incremental);
    RUN(test_apply_zero_is_identity_and_matches_kat);
    RUN(test_apply_exceeds_max_jump_ceiling);
    RUN(test_words_bytes_roundtrip_be_convention);

    printf("\n— Wire-кадр 0x9E —\n");
    RUN(test_parse_golden_frame);
    RUN(test_parse_rejects_garbage);
    RUN(test_parse_then_advance_roundtrip);

    printf("\n════════════════════════════════════════════════════════════════════\n");
    printf("Passed: %d, Failed: %d\n", tests_passed, tests_failed);
    return tests_failed == 0 ? 0 : 1;
}
