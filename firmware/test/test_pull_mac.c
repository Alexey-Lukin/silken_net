// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * test_pull_mac.c — [SEC.38] host-тести MAC над Queen-pull запитом
 * (queen/pull_mac.h).
 *
 * Golden-вектори пораховано OpenSSL::HMAC у Ruby — ті самі байти заморожено у
 * spec/services/downlink/pull_mac_spec.rb, тож C-білдер і Rails-перевірка не
 * можуть розійтись мовчки. Ключ — байти 00..1F; у RAM Королеви він лежить
 * словами 0x00010203…, як їх пише CommandBuilder (`-w32`), і саме цю
 * перестановку тест і фіксує першим. Компілюється x86 gcc, без ARM toolchain.
 */
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "../queen/pull_mac.h"

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
#define ASSERT_STR(got, want) do { \
    if (strcmp((got), (want)) != 0) { \
        printf(" ❌ FAIL (line %d: got %s, expected %s)\n", __LINE__, (got), (want)); \
        tests_failed++; return; \
    } \
} while(0)

/* KEYC 00 01 02 … 1F у тій формі, в якій його тримає RAM Королеви. */
static const uint32_t kKeycWords[PULL_MAC_KEY_WORDS] = {
    0x00010203u, 0x04050607u, 0x08090A0Bu, 0x0C0D0E0Fu,
    0x10111213u, 0x14151617u, 0x18191A1Bu, 0x1C1D1E1Fu,
};

TEST(test_keyc_words_become_big_endian_bytes) {
    uint8_t bytes[32];
    Pull_Mac_Keyc_Bytes(kKeycWords, bytes);
    for (int i = 0; i < 32; i++) ASSERT_EQ(bytes[i], i);
}

TEST(test_golden_poll_with_fw_and_cmd) {
    char q[PULL_MAC_QUERY_LEN + 1u];
    ASSERT_TRUE(Pull_Mac_Query(kKeycWords, "poll", "SNET-Q-00000001", 4660,
                               "fw=7", "cmd=0f1e2d3c-4b5a-6978-8796-a5b4c3d2e1f0", NULL, q));
    ASSERT_STR(q, "m=4919db6f8e65d85e178ac31330b5f73f");
}

TEST(test_golden_poll_fw_only_skips_missing_query) {
    char q[PULL_MAC_QUERY_LEN + 1u];
    ASSERT_TRUE(Pull_Mac_Query(kKeycWords, "poll", "SNET-Q-00000001", 1, "fw=0", NULL, NULL, q));
    ASSERT_STR(q, "m=be29f3cefc29a8a9550fce0089cdd998");
}

TEST(test_golden_ota_route_is_part_of_the_mac) {
    char q[PULL_MAC_QUERY_LEN + 1u];
    ASSERT_TRUE(Pull_Mac_Query(kKeycWords, "ota", "SNET-Q-00000001", 65535, "v=12", "ch=3", NULL, q));
    ASSERT_STR(q, "m=84e60570ae08fb40967c76f9a90fefda");
}

/* Будь-яке поле запиту змінює MAC — інакше його можна було б підробити. */
TEST(test_every_field_moves_the_mac) {
    char base[PULL_MAC_QUERY_LEN + 1u], other[PULL_MAC_QUERY_LEN + 1u];
    ASSERT_TRUE(Pull_Mac_Query(kKeycWords, "poll", "SNET-Q-00000001", 1, "fw=0", NULL, NULL, base));
    ASSERT_TRUE(Pull_Mac_Query(kKeycWords, "poll", "SNET-Q-00000001", 1, "fw=1", NULL, NULL, other));
    ASSERT_TRUE(strcmp(base, other) != 0);
    ASSERT_TRUE(Pull_Mac_Query(kKeycWords, "poll", "SNET-Q-00000002", 1, "fw=0", NULL, NULL, other));
    ASSERT_TRUE(strcmp(base, other) != 0);
    ASSERT_TRUE(Pull_Mac_Query(kKeycWords, "poll", "SNET-Q-00000001", 2, "fw=0", NULL, NULL, other));
    ASSERT_TRUE(strcmp(base, other) != 0);
    uint32_t other_key[PULL_MAC_KEY_WORDS];
    memcpy(other_key, kKeycWords, sizeof other_key);
    other_key[7] ^= 1u;
    ASSERT_TRUE(Pull_Mac_Query(other_key, "poll", "SNET-Q-00000001", 1, "fw=0", NULL, NULL, other));
    ASSERT_TRUE(strcmp(base, other) != 0);
}

TEST(test_oversized_canonical_refuses) {
    char q[PULL_MAC_QUERY_LEN + 1u];
    char long_q[200];
    memset(long_q, 'x', sizeof long_q - 1u);
    long_q[sizeof long_q - 1u] = '\0';
    ASSERT_EQ(Pull_Mac_Query(kKeycWords, "poll", "SNET-Q-00000001", 1, long_q, NULL, NULL, q), 0);
}

/* [FW.60] Nonce — третя опція перед m=; той самий вектор заморожено в pull_mac_spec.rb. */
TEST(test_golden_poll_with_nonce) {
    static const uint8_t nonce[PULL_MAC_NONCE_BYTES] = { 0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77 };
    char qn[PULL_MAC_NONCE_QUERY_LEN + 1u];
    char q[PULL_MAC_QUERY_LEN + 1u];
    Pull_Mac_Nonce_Query(nonce, qn);
    ASSERT_STR(qn, "n=0011223344556677");
    ASSERT_TRUE(Pull_Mac_Query(kKeycWords, "poll", "SNET-Q-00000001", 1, "fw=0", NULL, qn, q));
    ASSERT_STR(q, "m=5c56260210a15a778bec42dcd5a29a4a");
}

TEST(test_zero_keyc_refuses) {
    static const uint32_t zero[PULL_MAC_KEY_WORDS] = { 0 };
    char q[PULL_MAC_QUERY_LEN + 1u];
    ASSERT_EQ(Pull_Mac_Query(zero, "poll", "SNET-Q-00000001", 1, "fw=0", NULL, NULL, q), 0);
    ASSERT_EQ(Pull_Mac_Key_Is_Zero(kKeycWords), 0);
}

/* [FW.60] Тег відповіді: той самий вектор заморожено в pull_mac_spec.rb (reply_tag). */
static const char kGoldenM[] = "4919db6f8e65d85e178ac31330b5f73f";

TEST(test_golden_reply_tag) {
    uint8_t env[48];
    uint8_t tag[PULL_MAC_REPLY_TAG_LEN];
    static const uint8_t want[PULL_MAC_REPLY_TAG_LEN] = {
        0x77, 0x6e, 0x75, 0x62, 0xd3, 0x00, 0x28, 0x76,
        0x6e, 0x3f, 0x56, 0xd2, 0x55, 0xf0, 0xf1, 0x1a,
    };
    for (int i = 0; i < 48; i++) env[i] = (uint8_t)i;
    Pull_Mac_Reply_Tag(kKeycWords, kGoldenM, env, sizeof env, tag);
    for (int i = 0; i < (int)PULL_MAC_REPLY_TAG_LEN; i++) ASSERT_EQ(tag[i], want[i]);
}

TEST(test_reply_verify_strips_tag_and_rejects_forgery) {
    char qm[PULL_MAC_QUERY_LEN + 1u] = "m=";
    uint8_t buf[48 + PULL_MAC_REPLY_TAG_LEN];
    uint16_t len = sizeof buf;
    memcpy(qm + 2, kGoldenM, PULL_MAC_HEX_LEN + 1u);
    for (int i = 0; i < 48; i++) buf[i] = (uint8_t)i;
    Pull_Mac_Reply_Tag(kKeycWords, kGoldenM, buf, 48, buf + 48);

    ASSERT_TRUE(Pull_Mac_Reply_Verify(kKeycWords, qm, buf, &len));
    ASSERT_EQ(len, 48);                      /* тег знято — лишився конверт */

    len = sizeof buf;
    buf[0] ^= 0x01u;                         /* зміна IV — саме та підробка, що переписує час */
    ASSERT_EQ(Pull_Mac_Reply_Verify(kKeycWords, qm, buf, &len), 0);
    ASSERT_EQ(len, sizeof buf);              /* відмова довжини не чіпає */
    buf[0] ^= 0x01u;

    qm[2] = (qm[2] == 'a') ? 'b' : 'a';      /* чужий запит — той самий конверт не чинний */
    ASSERT_EQ(Pull_Mac_Reply_Verify(kKeycWords, qm, buf, &len), 0);

    len = PULL_MAC_REPLY_TAG_LEN - 1u;       /* коротше за тег */
    ASSERT_EQ(Pull_Mac_Reply_Verify(kKeycWords, qm, buf, &len), 0);
}

int main(void) {
    printf("\n[SEC.38] Pull_Mac_Query — MAC над Queen-pull запитом\n");
    printf("══════════════════════════════════════════════════════════════\n");
    RUN(test_keyc_words_become_big_endian_bytes);
    RUN(test_golden_poll_with_fw_and_cmd);
    RUN(test_golden_poll_fw_only_skips_missing_query);
    RUN(test_golden_ota_route_is_part_of_the_mac);
    RUN(test_every_field_moves_the_mac);
    RUN(test_oversized_canonical_refuses);
    RUN(test_golden_poll_with_nonce);
    RUN(test_zero_keyc_refuses);
    RUN(test_golden_reply_tag);
    RUN(test_reply_verify_strips_tag_and_rejects_forgery);
    printf("\n══════════════════════════════════════════════════════════════\n");
    printf("Passed: %d, Failed: %d\n", tests_passed, tests_failed);
    return tests_failed == 0 ? 0 : 1;
}
