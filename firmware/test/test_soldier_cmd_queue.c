// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * test_soldier_cmd_queue.c — [FW.20-Q2] черга Soldier-bound команд (host).
 *
 * Валідатор спільного каркаса [маркер][len_le:2][body][crc16_le:2],
 * дедуп-refresh, shot-бюджет, round-robin, евікція. Golden-кадр 0x9E
 * (9E 0400 0300 5C48) — той самий freeze-contract, що в test_key_ratchet.c
 * ↔ OtaPackagerService.build_rotate_key_block; інтеграційний кейс жене
 * блок з черги крізь справжній Key_Ratchet_Parse_Cmd — шлях Солдата.
 *
 * Build: make -C firmware/test cmd_queue
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#include "../queen/soldier_cmd_queue.h"
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

/* Freeze-contract hex з бекенда: [0x9E][len=4][target=3][crc16_le]. */
static const uint8_t GOLDEN_9E[] = { 0x9E, 0x04, 0x00, 0x03, 0x00, 0x5C, 0x48 };

/* Конструктор кадру спільного каркаса (дзеркало OtaPackagerService). */
static uint16_t build_frame(uint8_t *out, uint8_t marker,
                            const uint8_t *body, uint8_t body_len)
{
    uint16_t payload_len = (uint16_t)(body_len + SOLDIER_CMD_CRC_SIZE);
    out[0] = marker;
    out[1] = (uint8_t)(payload_len & 0xFFu);
    out[2] = (uint8_t)(payload_len >> 8);
    memcpy(out + 3, body, body_len);
    uint16_t crc = Silken_Crc16_Ccitt(body, body_len);
    out[3 + body_len]     = (uint8_t)(crc & 0xFFu);
    out[3 + body_len + 1] = (uint8_t)(crc >> 8);
    return (uint16_t)(SOLDIER_CMD_HEADER_SIZE + payload_len);
}

/* 0x9E з довільним target — для роздільних кадрів у тестах черги. */
static uint16_t build_rotate(uint8_t *out, uint16_t target)
{
    uint8_t body[2] = { (uint8_t)(target & 0xFFu), (uint8_t)(target >> 8) };
    return build_frame(out, SOLDIER_CMD_MARKER_ROTATE_KEY, body, 2);
}

/* ════════════════════════════════════════════════════════════════════
 * 1. Валідатор каркаса
 * ════════════════════════════════════════════════════════════════════ */
TEST(test_valid_golden_9e) {
    ASSERT_TRUE(Soldier_Cmd_Frame_Valid(GOLDEN_9E, sizeof GOLDEN_9E));
    /* CBC-padded хвіст (Handle_CoAP_Command віддає aligned-розмір) — теж ок. */
    uint8_t padded[16] = {0};
    memcpy(padded, GOLDEN_9E, sizeof GOLDEN_9E);
    ASSERT_TRUE(Soldier_Cmd_Frame_Valid(padded, 16));
}

TEST(test_valid_9a_thresholds_frame) {
    /* [FW.8] 8-байтний body: z_min/z_max/z_opt ×100 LE + species + version. */
    const uint8_t body[8] = { 0xC8, 0x00, 0x94, 0x11, 0x54, 0x0B, 0x02, 0x01 };
    uint8_t frame[16];
    uint16_t n = build_frame(frame, SOLDIER_CMD_MARKER_THRESHOLDS, body, 8);
    ASSERT_EQ(n, 13);
    ASSERT_TRUE(Soldier_Cmd_Frame_Valid(frame, n));
}

TEST(test_reject_foreign_marker) {
    /* 0x99 (OTA) і 0x9B (HMAC-печатка) мають власні гілки — у чергу зась. */
    uint8_t frame[16];
    uint16_t n = build_frame(frame, 0x99, (const uint8_t[]){ 0x01 }, 1);
    ASSERT_FALSE(Soldier_Cmd_Frame_Valid(frame, n));
    n = build_frame(frame, 0x9B, (const uint8_t[]){ 0x01 }, 1);
    ASSERT_FALSE(Soldier_Cmd_Frame_Valid(frame, n));
}

TEST(test_reject_short_and_lying_len) {
    ASSERT_FALSE(Soldier_Cmd_Frame_Valid(GOLDEN_9E, 5));  /* куций буфер */
    uint8_t frame[16];
    memcpy(frame, GOLDEN_9E, sizeof GOLDEN_9E);
    frame[1] = 0x0F;  /* len бреше: 3+15 > 16 — не лізе в LoRa-блок */
    ASSERT_FALSE(Soldier_Cmd_Frame_Valid(frame, 16));
    frame[1] = 0x08;  /* len бреше: 3+8 > наданих 7 байтів */
    ASSERT_FALSE(Soldier_Cmd_Frame_Valid(frame, sizeof GOLDEN_9E));
    frame[1] = 0x02;  /* len = лише CRC, body порожній */
    ASSERT_FALSE(Soldier_Cmd_Frame_Valid(frame, sizeof GOLDEN_9E));
}

TEST(test_reject_flipped_crc) {
    uint8_t frame[sizeof GOLDEN_9E];
    memcpy(frame, GOLDEN_9E, sizeof GOLDEN_9E);
    frame[3] ^= 0x01;  /* біт збрехав у LTE-транзиті */
    ASSERT_FALSE(Soldier_Cmd_Frame_Valid(frame, sizeof frame));
}

/* ════════════════════════════════════════════════════════════════════
 * 2. Черга: push / дедуп / бюджет / round-robin / евікція
 * ════════════════════════════════════════════════════════════════════ */
TEST(test_push_pads_block_and_next_pops_it) {
    SoldierCmdQueue q;
    uint8_t out[SOLDIER_CMD_BLOCK_SIZE];
    Soldier_Cmd_Queue_Init(&q);
    ASSERT_FALSE(Soldier_Cmd_Queue_Next(&q, out));  /* порожня — тиша */
    ASSERT_TRUE(Soldier_Cmd_Queue_Push(&q, GOLDEN_9E, sizeof GOLDEN_9E));
    ASSERT_TRUE(Soldier_Cmd_Queue_Next(&q, out));
    ASSERT_EQ(memcmp(out, GOLDEN_9E, sizeof GOLDEN_9E), 0);
    for (unsigned i = sizeof GOLDEN_9E; i < SOLDIER_CMD_BLOCK_SIZE; i++)
        ASSERT_EQ(out[i], 0);  /* zero-pad до AES-блоку */
}

TEST(test_push_rejects_invalid_leaves_queue_empty) {
    SoldierCmdQueue q;
    uint8_t out[SOLDIER_CMD_BLOCK_SIZE];
    uint8_t bad[sizeof GOLDEN_9E];
    Soldier_Cmd_Queue_Init(&q);
    memcpy(bad, GOLDEN_9E, sizeof bad);
    bad[4] ^= 0x80;
    ASSERT_FALSE(Soldier_Cmd_Queue_Push(&q, bad, sizeof bad));
    ASSERT_FALSE(Soldier_Cmd_Queue_Next(&q, out));
}

TEST(test_shot_budget_exhausts_exactly) {
    SoldierCmdQueue q;
    uint8_t out[SOLDIER_CMD_BLOCK_SIZE];
    Soldier_Cmd_Queue_Init(&q);
    ASSERT_TRUE(Soldier_Cmd_Queue_Push(&q, GOLDEN_9E, sizeof GOLDEN_9E));
    for (unsigned i = 0; i < SOLDIER_CMD_SHOT_BUDGET; i++)
        ASSERT_TRUE(Soldier_Cmd_Queue_Next(&q, out));
    ASSERT_FALSE(Soldier_Cmd_Queue_Next(&q, out));  /* бюджет згас — слот вільний */
}

TEST(test_dedup_refreshes_budget_not_slots) {
    SoldierCmdQueue q;
    uint8_t out[SOLDIER_CMD_BLOCK_SIZE];
    Soldier_Cmd_Queue_Init(&q);
    ASSERT_TRUE(Soldier_Cmd_Queue_Push(&q, GOLDEN_9E, sizeof GOLDEN_9E));
    for (unsigned i = 0; i < 10; i++)
        ASSERT_TRUE(Soldier_Cmd_Queue_Next(&q, out));
    /* Sidekiq retry приніс той самий кадр — бюджет повний, слот один. */
    ASSERT_TRUE(Soldier_Cmd_Queue_Push(&q, GOLDEN_9E, sizeof GOLDEN_9E));
    for (unsigned i = 0; i < SOLDIER_CMD_SHOT_BUDGET; i++)
        ASSERT_TRUE(Soldier_Cmd_Queue_Next(&q, out));
    ASSERT_FALSE(Soldier_Cmd_Queue_Next(&q, out));
}

TEST(test_round_robin_no_starvation) {
    SoldierCmdQueue q;
    uint8_t a[16], b[16], out[SOLDIER_CMD_BLOCK_SIZE];
    Soldier_Cmd_Queue_Init(&q);
    uint16_t na = build_rotate(a, 3);
    uint16_t nb = build_rotate(b, 4);
    ASSERT_TRUE(Soldier_Cmd_Queue_Push(&q, a, na));
    ASSERT_TRUE(Soldier_Cmd_Queue_Push(&q, b, nb));
    /* Два кадри чергуються — жоден не голодує. */
    ASSERT_TRUE(Soldier_Cmd_Queue_Next(&q, out));
    ASSERT_EQ(memcmp(out, a, na), 0);
    ASSERT_TRUE(Soldier_Cmd_Queue_Next(&q, out));
    ASSERT_EQ(memcmp(out, b, nb), 0);
    ASSERT_TRUE(Soldier_Cmd_Queue_Next(&q, out));
    ASSERT_EQ(memcmp(out, a, na), 0);
}

TEST(test_overflow_evicts_lowest_budget) {
    SoldierCmdQueue q;
    uint8_t frames[SOLDIER_CMD_QUEUE_SLOTS + 1][16];
    uint16_t sizes[SOLDIER_CMD_QUEUE_SLOTS + 1];
    uint8_t out[SOLDIER_CMD_BLOCK_SIZE];
    Soldier_Cmd_Queue_Init(&q);
    for (uint16_t i = 0; i <= SOLDIER_CMD_QUEUE_SLOTS; i++)
        sizes[i] = build_rotate(frames[i], (uint16_t)(i + 1));
    /* Заповнюємо всі слоти й відстрілюємо по разу round-robin'ом… */
    for (uint16_t i = 0; i < SOLDIER_CMD_QUEUE_SLOTS; i++)
        ASSERT_TRUE(Soldier_Cmd_Queue_Push(&q, frames[i], sizes[i]));
    ASSERT_TRUE(Soldier_Cmd_Queue_Next(&q, out));
    /* …слот #0 тепер найбідніший — саме він і стає жертвою п'ятого кадру. */
    ASSERT_TRUE(Soldier_Cmd_Queue_Push(&q, frames[SOLDIER_CMD_QUEUE_SLOTS],
                                       sizes[SOLDIER_CMD_QUEUE_SLOTS]));
    uint8_t seen_evicted = 0;
    uint8_t seen_newcomer = 0;
    for (unsigned i = 0; i < SOLDIER_CMD_QUEUE_SLOTS; i++) {
        ASSERT_TRUE(Soldier_Cmd_Queue_Next(&q, out));
        if (memcmp(out, frames[0], sizes[0]) == 0) seen_evicted = 1;
        if (memcmp(out, frames[SOLDIER_CMD_QUEUE_SLOTS],
                   sizes[SOLDIER_CMD_QUEUE_SLOTS]) == 0) seen_newcomer = 1;
    }
    ASSERT_TRUE(seen_newcomer);
    ASSERT_FALSE(seen_evicted);
}

/* ════════════════════════════════════════════════════════════════════
 * 3. Інтеграція: блок із черги → справжній парсер Солдата
 * ════════════════════════════════════════════════════════════════════ */
TEST(test_popped_block_parses_as_soldier_would) {
    SoldierCmdQueue q;
    uint8_t out[SOLDIER_CMD_BLOCK_SIZE];
    uint16_t target = 0;
    Soldier_Cmd_Queue_Init(&q);
    ASSERT_TRUE(Soldier_Cmd_Queue_Push(&q, GOLDEN_9E, sizeof GOLDEN_9E));
    ASSERT_TRUE(Soldier_Cmd_Queue_Next(&q, out));
    /* Солдат бачить рівно 16-байтний дешифрований блок — парсер його їсть. */
    ASSERT_TRUE(Key_Ratchet_Parse_Cmd(out, SOLDIER_CMD_BLOCK_SIZE, &target));
    ASSERT_EQ(target, 3);
}

/* ════════════════════════════════════════════════════════════════════ */
int main(void)
{
    printf("════════════════════════════════════════════════════════════════════\n");
    printf("  [FW.20-Q2] Черга Soldier-bound команд — валідатор + рефлекс-бюджет\n");
    printf("════════════════════════════════════════════════════════════════════\n");

    printf("\n— Валідатор каркаса —\n");
    RUN(test_valid_golden_9e);
    RUN(test_valid_9a_thresholds_frame);
    RUN(test_reject_foreign_marker);
    RUN(test_reject_short_and_lying_len);
    RUN(test_reject_flipped_crc);

    printf("\n— Черга —\n");
    RUN(test_push_pads_block_and_next_pops_it);
    RUN(test_push_rejects_invalid_leaves_queue_empty);
    RUN(test_shot_budget_exhausts_exactly);
    RUN(test_dedup_refreshes_budget_not_slots);
    RUN(test_round_robin_no_starvation);
    RUN(test_overflow_evicts_lowest_budget);

    printf("\n— Інтеграція з парсером Солдата —\n");
    RUN(test_popped_block_parses_as_soldier_would);

    printf("\n════════════════════════════════════════════════════════════════════\n");
    printf("Passed: %d, Failed: %d\n", tests_passed, tests_failed);
    return tests_failed == 0 ? 0 : 1;
}
