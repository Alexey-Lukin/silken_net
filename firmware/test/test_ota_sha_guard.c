// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * test_ota_sha_guard.c — [FW.52] host-тести Ota_Sha_Persist/Verify
 * (queen/ota_sha_guard.h).
 *
 * RAM-мок Queen's сторінки 125 (8 dw — record потребує лише 5, запас про
 * симетрію з test_flash_ota.c) + fault-injection (erase/program «помирає»
 * = power-cut). Доводить: round-trip, **magic-LAST** порядок (power-cut
 * перед magic → dw[0]=0xFF → Verify бачить невалідну магію → fail-closed,
 * НІКОЛИ не хибне "збіглося"), erase-fail, undersize/NULL reject, і сáме
 * ядро FW.52: збіг вмісту → serve, розбіжність/нічого не персистовано →
 * reject. Компілюється x86 gcc, без ARM toolchain.
 */
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "../queen/ota_sha_guard.h"

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

/* ── RAM-мок сторінки 125 + fault-injection (той самий шаблон, що
 * test_flash_ota.c's MockOta) ── */
#define SHA_PAGE_DWS 8u
typedef struct {
    uint64_t mem[SHA_PAGE_DWS];
    int erase_count;
    int program_count;
    int die_after_programs; /* -1 = ніколи; інакше відмова після N program */
    int die_on_erase;       /* 1 = erase повертає 0 */
} MockShaFlash;

static void mock_init(MockShaFlash *f) {
    memset(f->mem, 0xFF, sizeof f->mem);
    f->erase_count = 0;
    f->program_count = 0;
    f->die_after_programs = -1;
    f->die_on_erase = 0;
}
static uint64_t sha_read(void *io, uint32_t byte_off) {
    return ((MockShaFlash *)io)->mem[byte_off / 8u];
}
static int sha_program(void *io, uint32_t byte_off, uint64_t v) {
    MockShaFlash *f = (MockShaFlash *)io;
    if (f->die_after_programs == 0) return 0; /* power-cut: dw лишився 0xFF */
    if (f->die_after_programs > 0) f->die_after_programs--;
    f->mem[byte_off / 8u] = v;
    f->program_count++;
    return 1;
}
static int sha_erase(void *io, uint8_t page) {
    MockShaFlash *f = (MockShaFlash *)io;
    (void)page;
    if (f->die_on_erase) return 0;
    memset(f->mem, 0xFF, sizeof f->mem);
    f->erase_count++;
    return 1;
}
static const FlashKvOps sha_ops = { sha_read, sha_program, sha_erase };

static MockShaFlash flash;
#define FF64 0xFFFFFFFFFFFFFFFFull

static const uint8_t kBytecodeA[64] = {
    0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C,
    0x0D, 0x0E, 0x0F, 0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18,
    0x19, 0x1A, 0x1B, 0x1C, 0x1D, 0x1E, 0x1F, 0x20, 0x21, 0x22, 0x23, 0x24,
    0x25, 0x26, 0x27, 0x28, 0x29, 0x2A, 0x2B, 0x2C, 0x2D, 0x2E, 0x2F, 0x30,
    0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3A, 0x3B, 0x3C,
    0x3D, 0x3E, 0x3F, 0x40
};
/* Той самий розмір, ОДИН байт відрізняється — імітує "новий CoAP-push
 * почав перезаписувати буфер" (FW.52 сценарій (c)). */
static uint8_t kBytecodeB[64];

/* ── Запис + round-trip ── */

TEST(test_persist_roundtrip_verifies_true) {
    mock_init(&flash);
    ASSERT_TRUE(Ota_Sha_Persist(&sha_ops, &flash, kBytecodeA, sizeof kBytecodeA));
    ASSERT_EQ(flash.erase_count, 1);
    ASSERT_EQ((uint32_t)flash.mem[0], QUEEN_OTA_SHA_MAGIC);
    ASSERT_TRUE(Ota_Sha_Verify(&sha_ops, &flash, kBytecodeA, sizeof kBytecodeA));
}

TEST(test_persist_writes_5_doublewords) {
    mock_init(&flash);
    ASSERT_TRUE(Ota_Sha_Persist(&sha_ops, &flash, kBytecodeA, sizeof kBytecodeA));
    ASSERT_EQ(flash.program_count, 5);  /* 36 байт (4 magic + 32 sha256) → 5 dw */
}

TEST(test_persist_overwrites_previous_record) {
    mock_init(&flash);
    ASSERT_TRUE(Ota_Sha_Persist(&sha_ops, &flash, kBytecodeA, sizeof kBytecodeA));
    memcpy(kBytecodeB, kBytecodeA, sizeof kBytecodeA);
    kBytecodeB[0] ^= 0xFFu;
    ASSERT_TRUE(Ota_Sha_Persist(&sha_ops, &flash, kBytecodeB, sizeof kBytecodeB));
    ASSERT_EQ(flash.erase_count, 2);
    ASSERT_FALSE(Ota_Sha_Verify(&sha_ops, &flash, kBytecodeA, sizeof kBytecodeA));
    ASSERT_TRUE(Ota_Sha_Verify(&sha_ops, &flash, kBytecodeB, sizeof kBytecodeB));
}

/* ── FW.52 ядро: verify розрізняє "той самий буфер" від "уже чужий" ── */

TEST(test_verify_rejects_when_nothing_persisted) {
    /* Свіжа/стерта сторінка (fresh Queen boot, ще не було жодного OTA). */
    mock_init(&flash);
    ASSERT_FALSE(Ota_Sha_Verify(&sha_ops, &flash, kBytecodeA, sizeof kBytecodeA));
}

TEST(test_verify_true_when_buffer_untouched_since_persist) {
    /* (b) re-request для ТІЄЇ САМОЇ OTA після ota_is_active=0 — буфер не
     * чіпали відколи персистили, cross-check пропускає обслуговування. */
    mock_init(&flash);
    ASSERT_TRUE(Ota_Sha_Persist(&sha_ops, &flash, kBytecodeA, sizeof kBytecodeA));
    ASSERT_TRUE(Ota_Sha_Verify(&sha_ops, &flash, kBytecodeA, sizeof kBytecodeA));
}

TEST(test_verify_false_when_buffer_overwritten_same_size) {
    /* (c) re-request для ІНШОЇ OTA (hash mismatch, той самий розмір —
     * total_chunks-звірка сама по собі це б не впіймала) — reject, не
     * served-навмання чужий байткод. */
    mock_init(&flash);
    ASSERT_TRUE(Ota_Sha_Persist(&sha_ops, &flash, kBytecodeA, sizeof kBytecodeA));
    memcpy(kBytecodeB, kBytecodeA, sizeof kBytecodeA);
    kBytecodeB[sizeof(kBytecodeB) - 1] ^= 0xFFu;  /* один байт розійшовся */
    ASSERT_FALSE(Ota_Sha_Verify(&sha_ops, &flash, kBytecodeB, sizeof kBytecodeB));
}

TEST(test_verify_false_when_buffer_shorter_than_persisted) {
    /* Новий CoAP-push почав ЗБИРАННЯ меншої прошивки (pending_ota_size
     * менший за те, що персистили) — той самий клас, інший розмір. */
    mock_init(&flash);
    ASSERT_TRUE(Ota_Sha_Persist(&sha_ops, &flash, kBytecodeA, sizeof kBytecodeA));
    ASSERT_FALSE(Ota_Sha_Verify(&sha_ops, &flash, kBytecodeA, 32u));
}

/* ── Power-cut (magic-LAST safety) — дзеркало test_flash_ota.c ── */

TEST(test_magic_written_last) {
    mock_init(&flash);
    flash.die_after_programs = 4;  /* дозволити 4 body-dw (dw1..dw4), вбити magic (dw0) */
    ASSERT_FALSE(Ota_Sha_Persist(&sha_ops, &flash, kBytecodeA, sizeof kBytecodeA));
    ASSERT_EQ(flash.mem[0], FF64);              /* magic НЕ записаний → fail-closed */
    ASSERT_FALSE(flash.mem[1] == FF64);         /* тіло встигло лягти */
    ASSERT_FALSE(Ota_Sha_Verify(&sha_ops, &flash, kBytecodeA, sizeof kBytecodeA));
}

TEST(test_powercut_midbody_no_magic) {
    mock_init(&flash);
    flash.die_after_programs = 1;               /* помирає посеред тіла */
    ASSERT_FALSE(Ota_Sha_Persist(&sha_ops, &flash, kBytecodeA, sizeof kBytecodeA));
    ASSERT_EQ(flash.mem[0], FF64);
    ASSERT_FALSE(Ota_Sha_Verify(&sha_ops, &flash, kBytecodeA, sizeof kBytecodeA));
}

TEST(test_powercut_first_program_no_magic) {
    mock_init(&flash);
    flash.die_after_programs = 0;               /* перший program (dw1) падає */
    ASSERT_FALSE(Ota_Sha_Persist(&sha_ops, &flash, kBytecodeA, sizeof kBytecodeA));
    ASSERT_EQ(flash.mem[0], FF64);
}

TEST(test_erase_failure_aborts) {
    mock_init(&flash);
    flash.die_on_erase = 1;
    ASSERT_FALSE(Ota_Sha_Persist(&sha_ops, &flash, kBytecodeA, sizeof kBytecodeA));
    ASSERT_EQ(flash.program_count, 0);          /* не програмували після erase-fail */
}

/* ── Валідація входу ── */

TEST(test_rejects_null_and_zero_size) {
    mock_init(&flash);
    ASSERT_FALSE(Ota_Sha_Persist(&sha_ops, &flash, NULL, sizeof kBytecodeA));
    ASSERT_FALSE(Ota_Sha_Persist(&sha_ops, &flash, kBytecodeA, 0));
    ASSERT_FALSE(Ota_Sha_Persist(NULL, &flash, kBytecodeA, sizeof kBytecodeA));
    ASSERT_EQ(flash.erase_count, 0);

    ASSERT_FALSE(Ota_Sha_Verify(&sha_ops, &flash, NULL, sizeof kBytecodeA));
    ASSERT_FALSE(Ota_Sha_Verify(&sha_ops, &flash, kBytecodeA, 0));
    ASSERT_FALSE(Ota_Sha_Verify(NULL, &flash, kBytecodeA, sizeof kBytecodeA));
}

int main(void) {
    printf("\n[FW.52] Ota_Sha_Persist/Verify — Queen OTA SHA-256 cross-check\n");
    printf("══════════════════════════════════════════════════════════════\n");
    printf("\n— Запис + round-trip —\n");
    RUN(test_persist_roundtrip_verifies_true);
    RUN(test_persist_writes_5_doublewords);
    RUN(test_persist_overwrites_previous_record);
    printf("\n— FW.52 ядро: verify розрізняє свій буфер від чужого —\n");
    RUN(test_verify_rejects_when_nothing_persisted);
    RUN(test_verify_true_when_buffer_untouched_since_persist);
    RUN(test_verify_false_when_buffer_overwritten_same_size);
    RUN(test_verify_false_when_buffer_shorter_than_persisted);
    printf("\n— Power-cut (magic-LAST safety) —\n");
    RUN(test_magic_written_last);
    RUN(test_powercut_midbody_no_magic);
    RUN(test_powercut_first_program_no_magic);
    RUN(test_erase_failure_aborts);
    printf("\n— Валідація входу —\n");
    RUN(test_rejects_null_and_zero_size);
    printf("\n══════════════════════════════════════════════════════════════\n");
    printf("Passed: %d, Failed: %d\n", tests_passed, tests_failed);
    return tests_failed == 0 ? 0 : 1;
}
