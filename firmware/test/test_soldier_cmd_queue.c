// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * test_soldier_cmd_queue.c — [FW.20-Q2 · FW.17] черга адресних команд (host).
 *
 * Структурна перевірка без ключа, адресний пошук за DID, порядок за DLFC,
 * бюджет спроб у ціль, дедуп-освіження, жертва переповнення. Кадри — golden
 * CCM_KAT_DOWNLINK (ccm_kat_vectors.h): ті самі, що відкриває Dl_Ccm_Open у
 * test_downlink_ccm.c і будує Rails, тож «Королева віддає кадр байт-у-байт»
 * тут замикає ланцюг Rails → Королева → Солдат.
 *
 * Build: make -C firmware/test cmd_queue
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#include "../queen/soldier_cmd_queue.h"
#include "../common/ccm_kat_vectors.h"

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

static const uint8_t *golden(unsigned i) { return CCM_KAT_DOWNLINK[i].frame; }
static uint16_t golden_len(unsigned i) { return Dl_Ccm_Frame_Len(golden(i)[0]); }

/* Синтетичний кадр 0x9E для DID/DLFC_lsb: тіло й MIC Королеві байдужі. */
static void make_frame(uint8_t out[17], uint32_t did, uint16_t dlfc_lsb, uint8_t tag)
{
    memset(out, tag, 17);
    Build_DL_CCM_AAD(DL_CCM_OP_ROTATE_KEY, did, dlfc_lsb, out);
}

/* Скільки пострілів дасть черга для DID, доки не спорожніє. */
static unsigned drain_for(SoldierCmdQueue *q, uint32_t did)
{
    unsigned shots = 0;
    uint8_t out[DL_CCM_FRAME_MAX];
    for (int s; (s = Soldier_Cmd_Queue_Find_For(q, did)) >= 0; shots++) {
        (void)Soldier_Cmd_Queue_Take(q, s, out);
    }
    return shots;
}

TEST(test_accepts_every_golden_frame) {
    SoldierCmdQueue q;
    for (unsigned i = 0; i < CCM_KAT_DOWNLINK_COUNT; i++) {
        Soldier_Cmd_Queue_Init(&q);
        ASSERT_TRUE(Soldier_Cmd_Queue_Push(&q, golden(i), golden_len(i)));
    }
}

TEST(test_rejects_non_command_opcode_and_wrong_length) {
    SoldierCmdQueue q;
    Soldier_Cmd_Queue_Init(&q);
    uint8_t f[DL_CCM_FRAME_MAX];
    memcpy(f, golden(0), golden_len(0));
    ASSERT_EQ(Soldier_Cmd_Queue_Push(&q, f, 16), 0);  /* 16 Б — ECB-шлях, не команда */
    ASSERT_EQ(Soldier_Cmd_Queue_Push(&q, f, 18), 0);
    f[0] = 0x9C;                                        /* маяк — кластерний кадр */
    ASSERT_EQ(Soldier_Cmd_Queue_Push(&q, f, 17), 0);
    f[0] = 0x99;
    ASSERT_EQ(Soldier_Cmd_Queue_Push(&q, f, 17), 0);
    ASSERT_EQ(Soldier_Cmd_Queue_Find_For(&q, CCM_KAT_DOWNLINK[0].did), -1);
}

TEST(test_shoots_only_for_its_did) {
    SoldierCmdQueue q;
    Soldier_Cmd_Queue_Init(&q);
    ASSERT_TRUE(Soldier_Cmd_Queue_Push(&q, golden(1), golden_len(1)));
    ASSERT_EQ(Soldier_Cmd_Queue_Find_For(&q, CCM_KAT_DOWNLINK[0].did), -1);
    ASSERT_EQ(Soldier_Cmd_Queue_Find_For(&q, CCM_KAT_DOWNLINK[1].did ^ 1u), -1);
    ASSERT_TRUE(Soldier_Cmd_Queue_Find_For(&q, CCM_KAT_DOWNLINK[1].did) >= 0);
}

/* Королева віддає рівно той кадр, що приніс Rails: без шифрування й паддингу. */
TEST(test_take_passes_frame_byte_for_byte) {
    SoldierCmdQueue q;
    Soldier_Cmd_Queue_Init(&q);
    for (unsigned i = 0; i < CCM_KAT_DOWNLINK_COUNT; i++) {
        ASSERT_TRUE(Soldier_Cmd_Queue_Push(&q, golden(i), golden_len(i)));
    }
    for (unsigned i = 0; i < CCM_KAT_DOWNLINK_COUNT; i++) {
        uint8_t out[DL_CCM_FRAME_MAX] = {0};
        int s = Soldier_Cmd_Queue_Find_For(&q, CCM_KAT_DOWNLINK[i].did);
        ASSERT_TRUE(s >= 0);
        ASSERT_EQ(Soldier_Cmd_Queue_Take(&q, s, out), golden_len(i));
        ASSERT_EQ(memcmp(out, golden(i), golden_len(i)), 0);
    }
}

TEST(test_budget_is_attempts_at_the_target) {
    SoldierCmdQueue q;
    Soldier_Cmd_Queue_Init(&q);
    ASSERT_TRUE(Soldier_Cmd_Queue_Push(&q, golden(1), golden_len(1)));
    ASSERT_EQ(drain_for(&q, CCM_KAT_DOWNLINK[1].did), SOLDIER_CMD_SHOT_BUDGET);
    ASSERT_EQ(Soldier_Cmd_Queue_Find_For(&q, CCM_KAT_DOWNLINK[1].did), -1);
}

/* Rails перевидає відкриту команду тим самим кадром — слот не множиться. */
TEST(test_reissue_refreshes_budget_not_slots) {
    SoldierCmdQueue q;
    Soldier_Cmd_Queue_Init(&q);
    uint8_t out[DL_CCM_FRAME_MAX];
    ASSERT_TRUE(Soldier_Cmd_Queue_Push(&q, golden(0), golden_len(0)));
    int s = Soldier_Cmd_Queue_Find_For(&q, CCM_KAT_DOWNLINK[0].did);
    (void)Soldier_Cmd_Queue_Take(&q, s, out);
    ASSERT_TRUE(Soldier_Cmd_Queue_Push(&q, golden(0), golden_len(0)));
    ASSERT_EQ(drain_for(&q, CCM_KAT_DOWNLINK[0].did), SOLDIER_CMD_SHOT_BUDGET);
    unsigned live = 0;
    for (unsigned i = 0; i < SOLDIER_CMD_QUEUE_SLOTS; i++) live += q.shots[i] > 0u;
    ASSERT_EQ(live, 0);
}

/* Солдат приймає лише DLFC, строго більший за останній: молодша команда,
 * вистріляна раніше за старшу, зробила б старшу вічно мертвою. */
TEST(test_lowest_dlfc_first_for_one_did) {
    SoldierCmdQueue q;
    Soldier_Cmd_Queue_Init(&q);
    uint8_t f7[17], f5[17], out[DL_CCM_FRAME_MAX];
    make_frame(f7, 0xA1B2C3D4u, 7, 0x77);
    make_frame(f5, 0xA1B2C3D4u, 5, 0x55);
    ASSERT_TRUE(Soldier_Cmd_Queue_Push(&q, f7, 17));
    ASSERT_TRUE(Soldier_Cmd_Queue_Push(&q, f5, 17));
    for (unsigned n = 0; n < SOLDIER_CMD_SHOT_BUDGET; n++) {
        int s = Soldier_Cmd_Queue_Find_For(&q, 0xA1B2C3D4u);
        (void)Soldier_Cmd_Queue_Take(&q, s, out);
        ASSERT_EQ(Dl_Ccm_Frame_Dlfc_Lsb(out), 5);
    }
    int s = Soldier_Cmd_Queue_Find_For(&q, 0xA1B2C3D4u);
    (void)Soldier_Cmd_Queue_Take(&q, s, out);
    ASSERT_EQ(Dl_Ccm_Frame_Dlfc_Lsb(out), 7);
}

/* 16 біт ефіру обгортаються: 0xFFFF старший за 0x0001. */
TEST(test_dlfc_order_crosses_the_16_bit_wrap) {
    SoldierCmdQueue q;
    Soldier_Cmd_Queue_Init(&q);
    uint8_t lo[17], hi[17], out[DL_CCM_FRAME_MAX];
    make_frame(lo, 0x0BADF00Du, 0x0001u, 0x11);
    make_frame(hi, 0x0BADF00Du, 0xFFFFu, 0xFF);
    ASSERT_TRUE(Soldier_Cmd_Queue_Push(&q, lo, 17));
    ASSERT_TRUE(Soldier_Cmd_Queue_Push(&q, hi, 17));
    int s = Soldier_Cmd_Queue_Find_For(&q, 0x0BADF00Du);
    (void)Soldier_Cmd_Queue_Take(&q, s, out);
    ASSERT_EQ(Dl_Ccm_Frame_Dlfc_Lsb(out), 0xFFFF);
}

/* Переповнення витісняє найдавніше поставлене; освіжений дублікат молодшає.
 * Мовчазна ціль (команду ніхто не стріляв) не тримає слот вічно. */
TEST(test_overflow_evicts_the_oldest_push) {
    SoldierCmdQueue q;
    Soldier_Cmd_Queue_Init(&q);
    uint8_t f[SOLDIER_CMD_QUEUE_SLOTS + 1][17];
    for (unsigned i = 0; i <= SOLDIER_CMD_QUEUE_SLOTS; i++) {
        make_frame(f[i], 0x100u + i, (uint16_t)(i + 1u), (uint8_t)i);
    }
    for (unsigned i = 0; i < SOLDIER_CMD_QUEUE_SLOTS; i++) {
        ASSERT_TRUE(Soldier_Cmd_Queue_Push(&q, f[i], 17));
    }
    /* 0x100 постріляно (лишок менший) і освіжено повторною видачею —
     * найдавнішою стає 0x101, її й витісняє пʼята команда. */
    uint8_t out[DL_CCM_FRAME_MAX];
    (void)Soldier_Cmd_Queue_Take(&q, Soldier_Cmd_Queue_Find_For(&q, 0x100u), out);
    ASSERT_TRUE(Soldier_Cmd_Queue_Push(&q, f[0], 17));
    ASSERT_TRUE(Soldier_Cmd_Queue_Push(&q, f[SOLDIER_CMD_QUEUE_SLOTS], 17));
    ASSERT_TRUE(Soldier_Cmd_Queue_Find_For(&q, 0x100u) >= 0);
    ASSERT_EQ(Soldier_Cmd_Queue_Find_For(&q, 0x101u), -1);
    ASSERT_TRUE(Soldier_Cmd_Queue_Find_For(&q, 0x100u + SOLDIER_CMD_QUEUE_SLOTS) >= 0);
}

/* Під старим правилом «найменший лишок» постріляна жива ціль програвала б
 * мовчазним: тут вона стріляна, але поставлена ПІЗНІШЕ за мовчазні — лишається. */
TEST(test_live_target_is_not_evicted_for_silent_ones) {
    SoldierCmdQueue q;
    Soldier_Cmd_Queue_Init(&q);
    uint8_t f[SOLDIER_CMD_QUEUE_SLOTS + 1][17], out[DL_CCM_FRAME_MAX];
    for (unsigned i = 0; i <= SOLDIER_CMD_QUEUE_SLOTS; i++) {
        make_frame(f[i], 0x200u + i, (uint16_t)(i + 1u), (uint8_t)i);
    }
    for (unsigned i = 0; i < SOLDIER_CMD_QUEUE_SLOTS; i++) {
        ASSERT_TRUE(Soldier_Cmd_Queue_Push(&q, f[i], 17));
    }
    const uint32_t live = 0x200u + SOLDIER_CMD_QUEUE_SLOTS - 1u; /* поставлена останньою */
    for (unsigned n = 0; n + 1u < SOLDIER_CMD_SHOT_BUDGET; n++) {
        (void)Soldier_Cmd_Queue_Take(&q, Soldier_Cmd_Queue_Find_For(&q, live), out);
    }
    ASSERT_TRUE(Soldier_Cmd_Queue_Push(&q, f[SOLDIER_CMD_QUEUE_SLOTS], 17));
    ASSERT_TRUE(Soldier_Cmd_Queue_Find_For(&q, live) >= 0);
    ASSERT_EQ(Soldier_Cmd_Queue_Find_For(&q, 0x200u), -1);
}

int main(void)
{
    printf("════════════════════════════════════════════════════════════════════\n");
    printf("  [FW.20-Q2 · FW.17] Черга адресних команд Королеви\n");
    printf("════════════════════════════════════════════════════════════════════\n");

    RUN(test_accepts_every_golden_frame);
    RUN(test_rejects_non_command_opcode_and_wrong_length);
    RUN(test_shoots_only_for_its_did);
    RUN(test_take_passes_frame_byte_for_byte);
    RUN(test_budget_is_attempts_at_the_target);
    RUN(test_reissue_refreshes_budget_not_slots);
    RUN(test_lowest_dlfc_first_for_one_did);
    RUN(test_dlfc_order_crosses_the_16_bit_wrap);
    RUN(test_overflow_evicts_the_oldest_push);
    RUN(test_live_target_is_not_evicted_for_silent_ones);

    printf("════════════════════════════════════════════════════════════════════\n");
    printf("PASS: %d  FAIL: %d\n", tests_passed, tests_failed);
    return tests_failed == 0 ? 0 : 1;
}
