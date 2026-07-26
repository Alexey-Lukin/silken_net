// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * test_flash_ring.c — [ARCH.35] sector-ring W25Q32 (host).
 *
 * Мок — RAM з чесною NOR-семантикою (program лише 1→0, erase сектором)
 * + fault-injection: program/erase «гинуть» на k-тому виклику — power-cut
 * посеред операції. Ring 4-секторний (параметр mount'а), щоб wrap/drop
 * ганялись швидко; геометрія слота/бітмапів — бойова.
 *
 * Build: make -C firmware/test flash_ring
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#include "../common/flash_ring.h"

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

/* ════════════════════════════════════════════════════════════════════
 * RAM-мок NOR (4 сектори вистачає на всі сценарії)
 * ════════════════════════════════════════════════════════════════════ */
#define MOCK_SECTORS 4u

typedef struct {
    uint8_t mem[MOCK_SECTORS * FLASH_RING_SECTOR_SIZE];
    int     fail_program_after; /* -1 = вимкнено; 0 = наступний гине */
    int     fail_erase_after;
} MockFlash;

static int mock_read(void *io, uint32_t addr, uint8_t *buf, uint32_t len)
{
    MockFlash *m = (MockFlash *)io;
    memcpy(buf, m->mem + addr, len);
    return 1;
}

static int mock_program(void *io, uint32_t addr, const uint8_t *buf, uint32_t len)
{
    MockFlash *m = (MockFlash *)io;
    if (m->fail_program_after == 0) return 0; /* power-cut: нічого не лягло */
    if (m->fail_program_after > 0) m->fail_program_after--;
    for (uint32_t i = 0; i < len; i++) m->mem[addr + i] &= buf[i]; /* NOR 1→0 */
    return 1;
}

static int mock_erase(void *io, uint16_t sector)
{
    MockFlash *m = (MockFlash *)io;
    if (m->fail_erase_after == 0) return 0;
    if (m->fail_erase_after > 0) m->fail_erase_after--;
    memset(m->mem + (uint32_t)sector * FLASH_RING_SECTOR_SIZE, 0xFF,
           FLASH_RING_SECTOR_SIZE);
    return 1;
}

static const FlashRingOps mock_ops = { mock_read, mock_program, mock_erase };

static void mock_init(MockFlash *m)
{
    memset(m->mem, 0xFF, sizeof(m->mem)); /* цілинний/стертий флеш */
    m->fail_program_after = -1;
    m->fail_erase_after   = -1;
}

/* Детермінований 21-байтний запис: усі байти = f(seed). */
static void make_rec(uint8_t rec[FLASH_RING_RECORD_SIZE], uint8_t seed)
{
    for (uint8_t i = 0; i < FLASH_RING_RECORD_SIZE; i++)
        rec[i] = (uint8_t)(seed ^ (i * 7u));
}

#define ASSERT_REC(r, idx, seed) do { \
    uint8_t _got[FLASH_RING_RECORD_SIZE], _exp[FLASH_RING_RECORD_SIZE]; \
    ASSERT_TRUE(FlashRing_Read_Tail((r), (idx), _got)); \
    make_rec(_exp, (seed)); \
    ASSERT_EQ(memcmp(_got, _exp, FLASH_RING_RECORD_SIZE), 0); \
} while(0)

/* ════════════════════════════════════════════════════════════════════
 * 1. Базові: mount цілини, append/read roundtrip
 * ════════════════════════════════════════════════════════════════════ */
TEST(test_mount_virgin_is_empty) {
    MockFlash m; mock_init(&m);
    FlashRing r;
    ASSERT_TRUE(FlashRing_Mount(&r, &mock_ops, &m, MOCK_SECTORS));
    ASSERT_EQ(FlashRing_Count(&r), 0);
}

TEST(test_append_read_roundtrip_fifo) {
    MockFlash m; mock_init(&m);
    FlashRing r;
    ASSERT_TRUE(FlashRing_Mount(&r, &mock_ops, &m, MOCK_SECTORS));
    uint8_t rec[FLASH_RING_RECORD_SIZE];
    for (uint8_t i = 0; i < 10; i++) {
        make_rec(rec, i);
        ASSERT_TRUE(FlashRing_Append(&r, rec));
    }
    ASSERT_EQ(FlashRing_Count(&r), 10);
    ASSERT_REC(&r, 0, 0); /* FIFO: 0 = найстаріший */
    ASSERT_REC(&r, 9, 9);
}

/* ════════════════════════════════════════════════════════════════════
 * 2. Mount-scan відновлює стан (замість RTC-покажчиків з ескізу)
 * ════════════════════════════════════════════════════════════════════ */
TEST(test_remount_recovers_pointers_and_count) {
    MockFlash m; mock_init(&m);
    FlashRing r;
    ASSERT_TRUE(FlashRing_Mount(&r, &mock_ops, &m, MOCK_SECTORS));
    uint8_t rec[FLASH_RING_RECORD_SIZE];
    /* 200 записів = перетин межі сектора (192/сектор). */
    for (uint16_t i = 0; i < 200; i++) {
        make_rec(rec, (uint8_t)i);
        ASSERT_TRUE(FlashRing_Append(&r, rec));
    }
    FlashRing r2;
    ASSERT_TRUE(FlashRing_Mount(&r2, &mock_ops, &m, MOCK_SECTORS));
    ASSERT_EQ(FlashRing_Count(&r2), 200);
    ASSERT_EQ(r2.head_sector, r.head_sector);
    ASSERT_EQ(r2.head_slot, r.head_slot);
    ASSERT_EQ(r2.tail_sector, r.tail_sector);
    ASSERT_EQ(r2.tail_slot, r.tail_slot);
    ASSERT_REC(&r2, 0, 0);
    ASSERT_REC(&r2, 199, (uint8_t)199);
}

TEST(test_sector_rollover_increments_generation) {
    MockFlash m; mock_init(&m);
    FlashRing r;
    ASSERT_TRUE(FlashRing_Mount(&r, &mock_ops, &m, MOCK_SECTORS));
    uint8_t rec[FLASH_RING_RECORD_SIZE];
    make_rec(rec, 1);
    for (uint16_t i = 0; i <= FLASH_RING_SLOTS_PER_SECTOR; i++)
        ASSERT_TRUE(FlashRing_Append(&r, rec));
    ASSERT_EQ(r.head_sector, 1);
    ASSERT_EQ(r.head_seq, 2); /* два сектори = дві генерації */
}

/* ════════════════════════════════════════════════════════════════════
 * 3. Wrap: повний ring FIFO-дропає найстаріший СЕКТОР (durable)
 * ════════════════════════════════════════════════════════════════════ */
TEST(test_wrap_drops_oldest_sector) {
    MockFlash m; mock_init(&m);
    FlashRing r;
    ASSERT_TRUE(FlashRing_Mount(&r, &mock_ops, &m, MOCK_SECTORS));
    uint8_t rec[FLASH_RING_RECORD_SIZE];
    /* Місткість 4-секторного ring'а = 4×192; заповнюємо 4 сектори і ще 1
     * запис → head котиться у сектор tail'а → сектор 0 (записи 0..191)
     * дропається цілим. */
    uint32_t cap = (uint32_t)MOCK_SECTORS * FLASH_RING_SLOTS_PER_SECTOR;
    for (uint32_t i = 0; i < cap; i++) {
        make_rec(rec, (uint8_t)(i & 0xFFu));
        ASSERT_TRUE(FlashRing_Append(&r, rec));
    }
    ASSERT_EQ(FlashRing_Count(&r), cap);
    make_rec(rec, 0xAA);
    ASSERT_TRUE(FlashRing_Append(&r, rec));
    ASSERT_EQ(FlashRing_Count(&r), cap - FLASH_RING_SLOTS_PER_SECTOR + 1u);
    /* Найстаріший тепер — запис №192 (початок сектора 1). */
    ASSERT_REC(&r, 0, (uint8_t)(FLASH_RING_SLOTS_PER_SECTOR & 0xFFu));

    /* Drop durable: remount не воскрешає дропнуте. */
    FlashRing r2;
    ASSERT_TRUE(FlashRing_Mount(&r2, &mock_ops, &m, MOCK_SECTORS));
    ASSERT_EQ(FlashRing_Count(&r2), cap - FLASH_RING_SLOTS_PER_SECTOR + 1u);
    ASSERT_REC(&r2, 0, (uint8_t)(FLASH_RING_SLOTS_PER_SECTOR & 0xFFu));
}

/* ════════════════════════════════════════════════════════════════════
 * 4. Consume: durable FIFO-підтвердження доставки
 * ════════════════════════════════════════════════════════════════════ */
TEST(test_consume_advances_tail_durably) {
    MockFlash m; mock_init(&m);
    FlashRing r;
    ASSERT_TRUE(FlashRing_Mount(&r, &mock_ops, &m, MOCK_SECTORS));
    uint8_t rec[FLASH_RING_RECORD_SIZE];
    for (uint8_t i = 0; i < 10; i++) {
        make_rec(rec, i);
        ASSERT_TRUE(FlashRing_Append(&r, rec));
    }
    ASSERT_TRUE(FlashRing_Consume(&r, 4));
    ASSERT_EQ(FlashRing_Count(&r), 6);
    ASSERT_REC(&r, 0, 4);

    FlashRing r2;
    ASSERT_TRUE(FlashRing_Mount(&r2, &mock_ops, &m, MOCK_SECTORS));
    ASSERT_EQ(FlashRing_Count(&r2), 6);
    ASSERT_REC(&r2, 0, 4);
}

TEST(test_consume_across_sector_boundary) {
    MockFlash m; mock_init(&m);
    FlashRing r;
    ASSERT_TRUE(FlashRing_Mount(&r, &mock_ops, &m, MOCK_SECTORS));
    uint8_t rec[FLASH_RING_RECORD_SIZE];
    for (uint16_t i = 0; i < FLASH_RING_SLOTS_PER_SECTOR + 8u; i++) {
        make_rec(rec, (uint8_t)i);
        ASSERT_TRUE(FlashRing_Append(&r, rec));
    }
    ASSERT_TRUE(FlashRing_Consume(&r, FLASH_RING_SLOTS_PER_SECTOR + 3u));
    ASSERT_EQ(FlashRing_Count(&r), 5);
    ASSERT_EQ(r.tail_sector, 1);
    ASSERT_REC(&r, 0, (uint8_t)(FLASH_RING_SLOTS_PER_SECTOR + 3u));
}

TEST(test_drain_everything_then_continue_lifecycle) {
    /* Повний життєвий цикл «усе доставлено»: consume до нуля → remount
     * (mount без жодного pending: tail=head) → подальші append'и, включно
     * з прокатом head'а у наступний сектор ПОРОЖНІМ (tail їде слідом). */
    MockFlash m; mock_init(&m);
    FlashRing r;
    ASSERT_TRUE(FlashRing_Mount(&r, &mock_ops, &m, MOCK_SECTORS));
    uint8_t rec[FLASH_RING_RECORD_SIZE];
    /* Рівно до межі сектора: head_slot стає 192 — наступний append котить. */
    for (uint16_t i = 0; i < FLASH_RING_SLOTS_PER_SECTOR; i++) {
        make_rec(rec, (uint8_t)i);
        ASSERT_TRUE(FlashRing_Append(&r, rec));
    }
    ASSERT_TRUE(FlashRing_Consume(&r, FLASH_RING_SLOTS_PER_SECTOR));
    ASSERT_EQ(FlashRing_Count(&r), 0);

    FlashRing r2;
    ASSERT_TRUE(FlashRing_Mount(&r2, &mock_ops, &m, MOCK_SECTORS));
    ASSERT_EQ(FlashRing_Count(&r2), 0);

    /* Append у порожній ring з повним head-сектором: head котиться,
     * порожній tail слідує за ним — записи знову читаються FIFO. */
    make_rec(rec, 0xB7);
    ASSERT_TRUE(FlashRing_Append(&r2, rec));
    ASSERT_EQ(FlashRing_Count(&r2), 1);
    ASSERT_REC(&r2, 0, 0xB7);
}

TEST(test_consume_more_than_count_refused) {
    MockFlash m; mock_init(&m);
    FlashRing r;
    ASSERT_TRUE(FlashRing_Mount(&r, &mock_ops, &m, MOCK_SECTORS));
    uint8_t rec[FLASH_RING_RECORD_SIZE];
    make_rec(rec, 1);
    ASSERT_TRUE(FlashRing_Append(&r, rec));
    ASSERT_FALSE(FlashRing_Consume(&r, 2));
    ASSERT_EQ(FlashRing_Count(&r), 1);
}

/* ════════════════════════════════════════════════════════════════════
 * 5. Power-cut: чесні відмови без корупції
 * ════════════════════════════════════════════════════════════════════ */
TEST(test_powercut_before_used_bit_hides_slot) {
    MockFlash m; mock_init(&m);
    FlashRing r;
    ASSERT_TRUE(FlashRing_Mount(&r, &mock_ops, &m, MOCK_SECTORS));
    uint8_t rec[FLASH_RING_RECORD_SIZE];
    make_rec(rec, 1);
    ASSERT_TRUE(FlashRing_Append(&r, rec));
    /* Наступний Append: дані ляжуть (1-й program), used-біт — ні (2-й). */
    m.fail_program_after = 1;
    make_rec(rec, 2);
    ASSERT_FALSE(FlashRing_Append(&r, rec));
    m.fail_program_after = -1;

    FlashRing r2;
    ASSERT_TRUE(FlashRing_Mount(&r2, &mock_ops, &m, MOCK_SECTORS));
    ASSERT_EQ(FlashRing_Count(&r2), 1); /* напівзаписаний слот невидимий */
    ASSERT_REC(&r2, 0, 1);
    /* І слот не зрісся з наступним записом: новий append лягає поверх
     * сирітських байтів лише після erase нового покоління — а в межах
     * сектора head_slot з mount'а вказує на перший НЕ-used слот. */
    make_rec(rec, 3);
    ASSERT_TRUE(FlashRing_Append(&r2, rec));
    ASSERT_REC(&r2, 1, 3);
}

TEST(test_erase_fail_refuses_append_state_intact) {
    MockFlash m; mock_init(&m);
    FlashRing r;
    ASSERT_TRUE(FlashRing_Mount(&r, &mock_ops, &m, MOCK_SECTORS));
    m.fail_erase_after = 0;
    uint8_t rec[FLASH_RING_RECORD_SIZE];
    make_rec(rec, 1);
    ASSERT_FALSE(FlashRing_Append(&r, rec)); /* erase свіжого сектора згорів */
    ASSERT_EQ(FlashRing_Count(&r), 0);
    m.fail_erase_after = -1;
    ASSERT_TRUE(FlashRing_Append(&r, rec)); /* retry після відновлення живлення */
    ASSERT_EQ(FlashRing_Count(&r), 1);
}

TEST(test_powercut_mid_consume_redelivers_not_loses) {
    MockFlash m; mock_init(&m);
    FlashRing r;
    ASSERT_TRUE(FlashRing_Mount(&r, &mock_ops, &m, MOCK_SECTORS));
    uint8_t rec[FLASH_RING_RECORD_SIZE];
    for (uint8_t i = 0; i < 6; i++) {
        make_rec(rec, i);
        ASSERT_TRUE(FlashRing_Append(&r, rec));
    }
    /* Power-cut після 2 consumed-бітів з 5. */
    m.fail_program_after = 2;
    ASSERT_FALSE(FlashRing_Consume(&r, 5));
    m.fail_program_after = -1;

    FlashRing r2;
    ASSERT_TRUE(FlashRing_Mount(&r2, &mock_ops, &m, MOCK_SECTORS));
    /* At-least-once: 2 підтверджені зникли, 4 лишились на повторну
     * доставку (дублікат можливий, втрата — ні). */
    ASSERT_EQ(FlashRing_Count(&r2), 4);
    ASSERT_REC(&r2, 0, 2);
}

TEST(test_powercut_on_new_sector_header_refuses) {
    /* Свіжий сектор: erase успішний, але program ЗАГОЛОВКА гине (power-cut
     * між erase і записом hdr) → Append чесно відмовляє, лічильник стоїть;
     * після відновлення живлення retry лягає чисто. */
    MockFlash m; mock_init(&m);
    FlashRing r;
    ASSERT_TRUE(FlashRing_Mount(&r, &mock_ops, &m, MOCK_SECTORS));
    m.fail_program_after = 0; /* найперший program (заголовок нового сектора) гине */
    uint8_t rec[FLASH_RING_RECORD_SIZE];
    make_rec(rec, 1);
    ASSERT_FALSE(FlashRing_Append(&r, rec));
    ASSERT_EQ(FlashRing_Count(&r), 0);
    m.fail_program_after = -1;
    ASSERT_TRUE(FlashRing_Append(&r, rec));
    ASSERT_EQ(FlashRing_Count(&r), 1);
    ASSERT_REC(&r, 0, 1);
}

TEST(test_powercut_on_data_write_refuses) {
    /* Посеред сектора (head_slot>0): probe-цілинність ок, але program самих
     * ДАНИХ гине → Append відмовляє ще ДО used-біта (інваріант порядку 1):
     * напівзаписаний слот лишається невидимим, старі записи цілі. */
    MockFlash m; mock_init(&m);
    FlashRing r;
    ASSERT_TRUE(FlashRing_Mount(&r, &mock_ops, &m, MOCK_SECTORS));
    uint8_t rec[FLASH_RING_RECORD_SIZE];
    make_rec(rec, 1);
    ASSERT_TRUE(FlashRing_Append(&r, rec)); /* slot 0 лягає, head_slot→1 */
    m.fail_program_after = 0;               /* data-program 2-го запису гине */
    make_rec(rec, 2);
    ASSERT_FALSE(FlashRing_Append(&r, rec));
    m.fail_program_after = -1;
    ASSERT_EQ(FlashRing_Count(&r), 1);
    ASSERT_REC(&r, 0, 1);
}

/* ════════════════════════════════════════════════════════════════════ */
int main(void)
{
    printf("════════════════════════════════════════════════════════════════════\n");
    printf("  [ARCH.35] W25Q32 sector-ring — host NOR-мок + power-cut\n");
    printf("════════════════════════════════════════════════════════════════════\n");

    printf("\n— Базові + mount-scan —\n");
    RUN(test_mount_virgin_is_empty);
    RUN(test_append_read_roundtrip_fifo);
    RUN(test_remount_recovers_pointers_and_count);
    RUN(test_sector_rollover_increments_generation);

    printf("\n— Wrap / FIFO-drop —\n");
    RUN(test_wrap_drops_oldest_sector);

    printf("\n— Consume —\n");
    RUN(test_consume_advances_tail_durably);
    RUN(test_consume_across_sector_boundary);
    RUN(test_drain_everything_then_continue_lifecycle);
    RUN(test_consume_more_than_count_refused);

    printf("\n— Power-cut —\n");
    RUN(test_powercut_before_used_bit_hides_slot);
    RUN(test_erase_fail_refuses_append_state_intact);
    RUN(test_powercut_mid_consume_redelivers_not_loses);
    RUN(test_powercut_on_new_sector_header_refuses);
    RUN(test_powercut_on_data_write_refuses);

    printf("\n════════════════════════════════════════════════════════════════════\n");
    printf("Passed: %d, Failed: %d\n", tests_passed, tests_failed);
    return tests_failed == 0 ? 0 : 1;
}
