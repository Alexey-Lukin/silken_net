// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * test_flash_ota.c — [FW.52-г] host-тести Flash_Write_Contract (flash_ota.c).
 *
 * RAM-мок contract-сторінки (256 dw) + fault-injection (erase/program «помирає»
 * = power-cut). Доводить: round-trip, **magic-LAST** порядок (power-cut перед
 * magic → dw[0]=0xFF → boot не бачить RITE → fallback на embedded безпечний),
 * erase-fail, undersize/NULL reject. Компілюється x86 gcc, без ARM toolchain.
 */
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "../common/flash_ota.h"

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

/* ── RAM-мок contract-сторінки + fault-injection ── */
#define OTA_PAGE_DWS 256u
typedef struct {
    uint64_t mem[OTA_PAGE_DWS];
    int erase_count;
    int program_count;
    int die_after_programs; /* -1 = ніколи; інакше відмова після N program */
    int die_on_erase;       /* 1 = erase повертає 0 */
} MockOta;

static void mock_init(MockOta *f) {
    memset(f->mem, 0xFF, sizeof f->mem);
    f->erase_count = 0;
    f->program_count = 0;
    f->die_after_programs = -1;
    f->die_on_erase = 0;
}
static uint64_t ota_read(void *io, uint32_t byte_off) {
    return ((MockOta *)io)->mem[byte_off / 8u];
}
static int ota_program(void *io, uint32_t byte_off, uint64_t v) {
    MockOta *f = (MockOta *)io;
    if (f->die_after_programs == 0) return 0; /* power-cut: dw лишився 0xFF */
    if (f->die_after_programs > 0) f->die_after_programs--;
    f->mem[byte_off / 8u] = v;
    f->program_count++;
    return 1;
}
static int ota_erase(void *io, uint8_t page) {
    MockOta *f = (MockOta *)io;
    (void)page;
    if (f->die_on_erase) return 0;
    memset(f->mem, 0xFF, sizeof f->mem);
    f->erase_count++;
    return 1;
}
static const FlashKvOps ota_ops = { ota_read, ota_program, ota_erase };

static MockOta flash;
#define FF64 0xFFFFFFFFFFFFFFFFull

/* Тестовий байткод: RITE magic (LE) + 16 байт тіла → 20 байт = 3 dw (8+8+4). */
static const uint8_t kBytecode[20] = {
    0x52, 0x49, 0x54, 0x45,  /* "RITE" → uint32 LE 0x45544952 */
    0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
    0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10
};

TEST(test_write_roundtrip) {
    mock_init(&flash);
    ASSERT_TRUE(Flash_Write_Contract(&ota_ops, &flash, kBytecode, sizeof kBytecode));
    ASSERT_EQ(flash.erase_count, 1);
    ASSERT_EQ((uint32_t)flash.mem[0], OTA_CONTRACT_MAGIC); /* перші 4 байти LE = RITE */
    uint8_t out[20];
    memcpy(out, flash.mem, sizeof out);                   /* байткод збережено побайтово */
    ASSERT_EQ(memcmp(out, kBytecode, sizeof kBytecode), 0);
}

TEST(test_full_write_dw_count) {
    mock_init(&flash);
    ASSERT_TRUE(Flash_Write_Contract(&ota_ops, &flash, kBytecode, sizeof kBytecode));
    ASSERT_EQ(flash.program_count, 3);                    /* 20 байт → 3 dw */
}

TEST(test_magic_written_last) {
    /* Дозволити 2 body-dw, тоді вбити magic-program → dw[0] лишається 0xFF. */
    mock_init(&flash);
    flash.die_after_programs = 2;
    ASSERT_FALSE(Flash_Write_Contract(&ota_ops, &flash, kBytecode, sizeof kBytecode));
    ASSERT_EQ(flash.mem[0], FF64);                        /* magic НЕ записаний → boot fallback */
    ASSERT_FALSE(flash.mem[1] == FF64);                   /* тіло встигло лягти */
}

TEST(test_powercut_midbody_no_magic) {
    mock_init(&flash);
    flash.die_after_programs = 1;                         /* помирає посеред тіла */
    ASSERT_FALSE(Flash_Write_Contract(&ota_ops, &flash, kBytecode, sizeof kBytecode));
    ASSERT_EQ(flash.mem[0], FF64);                        /* magic ніколи не дійшов */
}

TEST(test_powercut_first_program_no_magic) {
    mock_init(&flash);
    flash.die_after_programs = 0;                         /* перший program падає */
    ASSERT_FALSE(Flash_Write_Contract(&ota_ops, &flash, kBytecode, sizeof kBytecode));
    ASSERT_EQ(flash.mem[0], FF64);
}

TEST(test_erase_failure_aborts) {
    mock_init(&flash);
    flash.die_on_erase = 1;
    ASSERT_FALSE(Flash_Write_Contract(&ota_ops, &flash, kBytecode, sizeof kBytecode));
    ASSERT_EQ(flash.program_count, 0);                    /* не програмували після erase-fail */
}

TEST(test_rejects_undersize) {
    mock_init(&flash);
    uint8_t tiny[3] = { 0x52, 0x49, 0x54 };
    ASSERT_FALSE(Flash_Write_Contract(&ota_ops, &flash, tiny, sizeof tiny));
    ASSERT_EQ(flash.erase_count, 0);                      /* навіть не стирали */
}

TEST(test_rejects_null) {
    mock_init(&flash);
    ASSERT_FALSE(Flash_Write_Contract(&ota_ops, &flash, NULL, 20));
    ASSERT_FALSE(Flash_Write_Contract(NULL, &flash, kBytecode, 20));
}

int main(void) {
    printf("\n[FW.52-г] Flash_Write_Contract — OTA contract blob writer\n");
    printf("══════════════════════════════════════════════════════════════\n");
    printf("\n— Запис + лічення —\n");
    RUN(test_write_roundtrip);
    RUN(test_full_write_dw_count);
    printf("\n— Power-cut (magic-LAST safety) —\n");
    RUN(test_magic_written_last);
    RUN(test_powercut_midbody_no_magic);
    RUN(test_powercut_first_program_no_magic);
    RUN(test_erase_failure_aborts);
    printf("\n— Валідація входу —\n");
    RUN(test_rejects_undersize);
    RUN(test_rejects_null);
    printf("\n══════════════════════════════════════════════════════════════\n");
    printf("Passed: %d, Failed: %d\n", tests_passed, tests_failed);
    return tests_failed == 0 ? 0 : 1;
}
