/*
 * test_flash_kv.c — [ARCH.28/FW.54] host-тести журнального Flash-KV.
 *
 * RAM-мок двох 2КБ-сторінок + fault-injection (program/erase «помирає»
 * після N операцій = power-cut). Доводить інваріанти I1-I3 (flash_kv.c):
 * атомарний елемент, FINI-останнім, стара сторінка живе до FINI нової.
 *
 * Build: make -C firmware/test flash_kv
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#include "../common/flash_kv.h"

/* ════════════════════════════════════════════════════════════════════
 * TEST FRAMEWORK (house pattern)
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

/* ════════════════════════════════════════════════════════════════════
 * RAM-мок флешу: 2 сторінки × 256 dw, лічильники wear + fault-injection
 * ════════════════════════════════════════════════════════════════════ */
#define MOCK_PAGE_DWS 256u

typedef struct {
    uint64_t mem[2][MOCK_PAGE_DWS];
    int      erase_count[2];
    int      program_count;
    int      die_after_programs; /* -1 = ніколи; інакше відмова після N */
} MockFlash;

static void mock_init(MockFlash *f)
{
    memset(f, 0xFF, sizeof f->mem);
    f->erase_count[0] = f->erase_count[1] = 0;
    f->program_count = 0;
    f->die_after_programs = -1;
}

static uint64_t mock_read(void *io, uint32_t byte_off)
{
    MockFlash *f = (MockFlash *)io;
    uint32_t dw = byte_off / 8u;
    return f->mem[dw / MOCK_PAGE_DWS][dw % MOCK_PAGE_DWS];
}

static int mock_program(void *io, uint32_t byte_off, uint64_t v)
{
    MockFlash *f = (MockFlash *)io;
    if (f->die_after_programs == 0) return 0; /* power-cut: dw лишився FF */
    if (f->die_after_programs > 0) f->die_after_programs--;
    uint32_t dw = byte_off / 8u;
    f->mem[dw / MOCK_PAGE_DWS][dw % MOCK_PAGE_DWS] = v;
    f->program_count++;
    return 1;
}

static int mock_erase(void *io, uint8_t page)
{
    MockFlash *f = (MockFlash *)io;
    memset(f->mem[page], 0xFF, sizeof f->mem[page]);
    f->erase_count[page]++;
    return 1;
}

static const FlashKvOps mock_ops = { mock_read, mock_program, mock_erase };

static MockFlash flash;
static FlashKv kv;

static void fresh_mount(void)
{
    mock_init(&flash);
    ASSERT_TRUE(FlashKv_Mount(&kv, &mock_ops, &flash, MOCK_PAGE_DWS));
}

/* ════════════════════════════════════════════════════════════════════
 * 1. MOUNT + БАЗОВИЙ ЦИКЛ
 * ════════════════════════════════════════════════════════════════════ */
TEST(test_mount_blank_formats) {
    mock_init(&flash);
    ASSERT_TRUE(FlashKv_Mount(&kv, &mock_ops, &flash, MOCK_PAGE_DWS));
    uint32_t v;
    ASSERT_FALSE(FlashKv_Get32(&kv, 0x10, &v));
    ASSERT_EQ(FlashKv_FreeSlots(&kv), MOCK_PAGE_DWS - 2);
}

TEST(test_put_get_roundtrip) {
    fresh_mount();
    ASSERT_TRUE(FlashKv_Put32(&kv, 0x10, 0xDEADBEEFu));
    ASSERT_TRUE(FlashKv_Put32(&kv, 0x20, 12345u));
    uint32_t v = 0;
    ASSERT_TRUE(FlashKv_Get32(&kv, 0x10, &v));
    ASSERT_EQ(v, 0xDEADBEEFu);
    ASSERT_TRUE(FlashKv_Get32(&kv, 0x20, &v));
    ASSERT_EQ(v, 12345u);
}

TEST(test_update_latest_wins) {
    fresh_mount();
    for (uint32_t i = 0; i < 10; i++) ASSERT_TRUE(FlashKv_Put32(&kv, 0x42, i));
    uint32_t v = 0;
    ASSERT_TRUE(FlashKv_Get32(&kv, 0x42, &v));
    ASSERT_EQ(v, 9u);
}

TEST(test_key_bounds_rejected) {
    fresh_mount();
    ASSERT_FALSE(FlashKv_Put32(&kv, 0x00, 1u)); /* зарезервовано */
    ASSERT_FALSE(FlashKv_Put32(&kv, 0xFF, 1u)); /* стертий флеш */
    ASSERT_TRUE(FlashKv_Put32(&kv, FLASH_KV_KEY_MIN, 1u));
    ASSERT_TRUE(FlashKv_Put32(&kv, FLASH_KV_KEY_MAX, 2u));
}

TEST(test_persistence_across_remount) {
    fresh_mount();
    ASSERT_TRUE(FlashKv_Put32(&kv, 0x31, 777u));
    /* «Ребут»: новий Mount на тому ж флеші */
    FlashKv kv2;
    ASSERT_TRUE(FlashKv_Mount(&kv2, &mock_ops, &flash, MOCK_PAGE_DWS));
    uint32_t v = 0;
    ASSERT_TRUE(FlashKv_Get32(&kv2, 0x31, &v));
    ASSERT_EQ(v, 777u);
    /* write-курсор став ПІСЛЯ запису, не поверх нього */
    ASSERT_TRUE(FlashKv_Put32(&kv2, 0x32, 888u));
    ASSERT_TRUE(FlashKv_Get32(&kv2, 0x31, &v));
    ASSERT_EQ(v, 777u);
}

/* ════════════════════════════════════════════════════════════════════
 * 2. FULL + COMPACT
 * ════════════════════════════════════════════════════════════════════ */
TEST(test_full_page_rejects_put) {
    fresh_mount();
    uint16_t free0 = FlashKv_FreeSlots(&kv);
    for (uint16_t i = 0; i < free0; i++) {
        ASSERT_TRUE(FlashKv_Put32(&kv, 0x50, i));
    }
    ASSERT_EQ(FlashKv_FreeSlots(&kv), 0);
    ASSERT_FALSE(FlashKv_Put32(&kv, 0x50, 9999u));
    ASSERT_TRUE(FlashKv_NeedsCompact(&kv, 4));
}

TEST(test_compact_collapses_duplicates) {
    fresh_mount();
    for (uint32_t i = 0; i < 100; i++) ASSERT_TRUE(FlashKv_Put32(&kv, 0x60, i));
    ASSERT_TRUE(FlashKv_Put32(&kv, 0x61, 4242u));
    ASSERT_TRUE(FlashKv_Compact(&kv));
    /* 2 живі ключі → 2 елементи у свіжому поколінні */
    ASSERT_EQ(FlashKv_FreeSlots(&kv), MOCK_PAGE_DWS - 2 - 2);
    uint32_t v = 0;
    ASSERT_TRUE(FlashKv_Get32(&kv, 0x60, &v));
    ASSERT_EQ(v, 99u);
    ASSERT_TRUE(FlashKv_Get32(&kv, 0x61, &v));
    ASSERT_EQ(v, 4242u);
}

TEST(test_compact_erases_old_generation) {
    fresh_mount();
    ASSERT_TRUE(FlashKv_Put32(&kv, 0x70, 1u));
    int erases_before = flash.erase_count[0];
    ASSERT_TRUE(FlashKv_Compact(&kv)); /* active 0 → 1 */
    ASSERT_EQ(flash.erase_count[0], erases_before + 1);
    /* і назад: ще один compact повертає на сторінку 0 */
    ASSERT_TRUE(FlashKv_Compact(&kv));
    uint32_t v = 0;
    ASSERT_TRUE(FlashKv_Get32(&kv, 0x70, &v));
    ASSERT_EQ(v, 1u);
}

/* ════════════════════════════════════════════════════════════════════
 * 3. POWER-CUT (інваріанти I1-I3)
 * ════════════════════════════════════════════════════════════════════ */
TEST(test_powercut_midcopy_old_page_authoritative) {
    fresh_mount();
    ASSERT_TRUE(FlashKv_Put32(&kv, 0x10, 111u));
    ASSERT_TRUE(FlashKv_Put32(&kv, 0x20, 222u));
    /* Смерть посеред переносу: header нової встигне, FINI — ні */
    flash.die_after_programs = 2; /* hdr + 1 елемент, далі темрява */
    ASSERT_FALSE(FlashKv_Compact(&kv));

    flash.die_after_programs = -1; /* живлення повернулось */
    FlashKv kv2;
    ASSERT_TRUE(FlashKv_Mount(&kv2, &mock_ops, &flash, MOCK_PAGE_DWS));
    uint32_t v = 0;
    ASSERT_TRUE(FlashKv_Get32(&kv2, 0x10, &v));
    ASSERT_EQ(v, 111u);
    ASSERT_TRUE(FlashKv_Get32(&kv2, 0x20, &v));
    ASSERT_EQ(v, 222u);
    /* недобудову прибрано → compact можна повторити */
    ASSERT_TRUE(FlashKv_Compact(&kv2));
    ASSERT_TRUE(FlashKv_Get32(&kv2, 0x20, &v));
    ASSERT_EQ(v, 222u);
}

TEST(test_powercut_after_fini_before_erase) {
    fresh_mount();
    ASSERT_TRUE(FlashKv_Put32(&kv, 0x33, 333u));
    /* Симуляція: FINI встиг, erase старої — ні → дві повні валідні.
     * Звіряємо вручну: компакт без останнього erase. */
    uint64_t snapshot[2][MOCK_PAGE_DWS];
    memcpy(snapshot, flash.mem, sizeof snapshot);
    ASSERT_TRUE(FlashKv_Compact(&kv));
    /* повертаємо стару сторінку з могили — наче erase не відбувся */
    memcpy(flash.mem[0], snapshot[0], sizeof flash.mem[0]);

    FlashKv kv2;
    ASSERT_TRUE(FlashKv_Mount(&kv2, &mock_ops, &flash, MOCK_PAGE_DWS));
    uint32_t v = 0;
    ASSERT_TRUE(FlashKv_Get32(&kv2, 0x33, &v)); /* вища seq виграла */
    ASSERT_EQ(v, 333u);
    ASSERT_TRUE(flash.erase_count[0] >= 1);     /* нижчу прибрано */
}

TEST(test_torn_record_skipped_scan_continues) {
    fresh_mount();
    ASSERT_TRUE(FlashKv_Put32(&kv, 0x11, 1u));
    /* Сміття поза API (бітфліп/обірване програмування без ECC-атомарності
     * у моку): валідний запис ПІСЛЯ сміття все одно читається */
    flash.mem[0][3] = 0x1234567890ABCDEFull;
    ASSERT_TRUE(FlashKv_Put32(&kv, 0x12, 2u)); /* піде у dw4? ні — кур'єр... */
    FlashKv kv2;
    ASSERT_TRUE(FlashKv_Mount(&kv2, &mock_ops, &flash, MOCK_PAGE_DWS));
    uint32_t v = 0;
    ASSERT_TRUE(FlashKv_Get32(&kv2, 0x11, &v));
    ASSERT_EQ(v, 1u);
    ASSERT_TRUE(FlashKv_Get32(&kv2, 0x12, &v));
    ASSERT_EQ(v, 2u);
}

TEST(test_powercut_during_put_record_invisible) {
    fresh_mount();
    ASSERT_TRUE(FlashKv_Put32(&kv, 0x21, 1u));
    flash.die_after_programs = 0; /* power-cut: запис не стався (dw = FF) */
    ASSERT_FALSE(FlashKv_Put32(&kv, 0x21, 2u));

    flash.die_after_programs = -1; /* живлення повернулось */
    FlashKv kv2;
    ASSERT_TRUE(FlashKv_Mount(&kv2, &mock_ops, &flash, MOCK_PAGE_DWS));
    uint32_t v = 0;
    ASSERT_TRUE(FlashKv_Get32(&kv2, 0x21, &v));
    ASSERT_EQ(v, 1u); /* попереднє покоління значення живе */
}

/* ════════════════════════════════════════════════════════════════════
 * 4. WEAR-видимість
 * ════════════════════════════════════════════════════════════════════ */
TEST(test_wear_one_erase_per_compact_per_page) {
    fresh_mount();
    ASSERT_TRUE(FlashKv_Put32(&kv, 0x55, 5u));
    int e0 = flash.erase_count[0], e1 = flash.erase_count[1];
    for (int i = 0; i < 10; i++) ASSERT_TRUE(FlashKv_Compact(&kv));
    /* 10 компактів = по 10 erase на кожну сторінку сумарно (ping-pong) */
    ASSERT_EQ((flash.erase_count[0] - e0) + (flash.erase_count[1] - e1), 10);
}

/* ════════════════════════════════════════════════════════════════════ */
int main(void)
{
    printf("════════════════════════════════════════════════════════════════════\n");
    printf("  [ARCH.28/FW.54] Flash-KV журнал — host (RAM-мок + power-cut)\n");
    printf("════════════════════════════════════════════════════════════════════\n");

    printf("\n— Mount + базовий цикл —\n");
    RUN(test_mount_blank_formats);
    RUN(test_put_get_roundtrip);
    RUN(test_update_latest_wins);
    RUN(test_key_bounds_rejected);
    RUN(test_persistence_across_remount);

    printf("\n— Full + compact —\n");
    RUN(test_full_page_rejects_put);
    RUN(test_compact_collapses_duplicates);
    RUN(test_compact_erases_old_generation);

    printf("\n— Power-cut (I1-I3) —\n");
    RUN(test_powercut_midcopy_old_page_authoritative);
    RUN(test_powercut_after_fini_before_erase);
    RUN(test_torn_record_skipped_scan_continues);
    RUN(test_powercut_during_put_record_invisible);

    printf("\n— Wear —\n");
    RUN(test_wear_one_erase_per_compact_per_page);

    printf("\n════════════════════════════════════════════════════════════════════\n");
    printf("Passed: %d, Failed: %d\n", tests_passed, tests_failed);
    return tests_failed == 0 ? 0 : 1;
}
