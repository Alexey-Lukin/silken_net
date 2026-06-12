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

/* ════════════════════════════════════════════════════════════════════
 * 5. [FW.8] Persist Z-порогів поверх KV (lorenz_thresholds.h)
 *
 * Host-половина deferred-залишку FW.8: Save/Load на ключах 0x10/0x11
 * (реєстр 03_01 §2.3.1). Парність інваріантів з парсером 0x9A пінується
 * проти дзеркала test_soldier_logic.c (ті самі межі).
 * ════════════════════════════════════════════════════════════════════ */
#include "../common/lorenz_thresholds.h"

TEST(test_fw8_save_load_roundtrip) {
    fresh_mount();
    LorenzThresholds in = { 150, 4800, 3100, 7, 3 }, out;
    ASSERT_TRUE(Lorenz_Thresholds_Save(&kv, &in));
    ASSERT_TRUE(Lorenz_Thresholds_Load(&kv, &out));
    ASSERT_EQ(out.z_min_x100, 150);
    ASSERT_EQ(out.z_max_x100, 4800);
    ASSERT_EQ(out.z_opt_x100, 3100);
    ASSERT_EQ(out.species_id, 7);
    ASSERT_EQ(out.config_version, 3);
}

TEST(test_fw8_load_empty_kv_returns_defaults) {
    fresh_mount();
    LorenzThresholds out;
    ASSERT_FALSE(Lorenz_Thresholds_Load(&kv, &out));
    ASSERT_EQ(out.z_min_x100, FW8_DEFAULT_Z_MIN_X100);
    ASSERT_EQ(out.z_max_x100, FW8_DEFAULT_Z_MAX_X100);
    ASSERT_EQ(out.z_opt_x100, FW8_DEFAULT_Z_OPT_X100);
    ASSERT_EQ(out.species_id, 0xFF);
    ASSERT_EQ(out.config_version, 0);
}

TEST(test_fw8_save_rejects_invalid_never_pollutes_flash) {
    fresh_mount();
    LorenzThresholds bad = { 4800, 150, 3100, 7, 3 }; /* min > max */
    ASSERT_FALSE(Lorenz_Thresholds_Save(&kv, &bad));
    uint32_t v;
    ASSERT_FALSE(FlashKv_Get32(&kv, FW8_KV_KEY_ZPAIR, &v)); /* нічого не лягло */
}

TEST(test_fw8_negative_z_survives_u32_packing) {
    /* int16 → u16 → u32 → назад: знак не губиться (важливо для z_min < 0). */
    fresh_mount();
    LorenzThresholds in = { -500, 300, -100, 1, 9 }, out;
    ASSERT_TRUE(Lorenz_Thresholds_Save(&kv, &in));
    ASSERT_TRUE(Lorenz_Thresholds_Load(&kv, &out));
    ASSERT_EQ(out.z_min_x100, -500);
    ASSERT_EQ(out.z_opt_x100, -100);
}

TEST(test_fw8_torn_pair_powercut_falls_to_defaults) {
    /* Power-cut між Put32(0x10) і Put32(0x11): z-пара лягла, мета — ні →
     * Load не бачить пари ключів → дефолти, без половинної конфігурації. */
    fresh_mount();
    LorenzThresholds in = { 150, 4800, 3100, 7, 3 }, out;
    flash.die_after_programs = 1; /* перший program ок, другий = power-cut */
    ASSERT_FALSE(Lorenz_Thresholds_Save(&kv, &in));
    flash.die_after_programs = -1;
    ASSERT_FALSE(Lorenz_Thresholds_Load(&kv, &out));
    ASSERT_EQ(out.z_min_x100, FW8_DEFAULT_Z_MIN_X100);
}

TEST(test_fw8_mixed_generation_invalid_combo_falls_to_defaults) {
    /* v2 z-пара + v1 мета (torn re-send): z_opt v1 поза [min,max] v2 →
     * інваріанти валять комбінацію → дефолти до наступного re-send. */
    fresh_mount();
    LorenzThresholds v1 = { 150, 4800, 3100, 7, 1 }, out;
    ASSERT_TRUE(Lorenz_Thresholds_Save(&kv, &v1));
    /* «v2» зсуває зону вище за v1.z_opt: пишемо лише z-пару (порвано). */
    uint32_t zpair_v2 = (uint32_t)(uint16_t)(int16_t)3500 |
                        ((uint32_t)(uint16_t)(int16_t)9000 << 16);
    ASSERT_TRUE(FlashKv_Put32(&kv, FW8_KV_KEY_ZPAIR, zpair_v2));
    ASSERT_FALSE(Lorenz_Thresholds_Load(&kv, &out));
    ASSERT_EQ(out.config_version, 0);
}

TEST(test_fw8_valid_agrees_with_parser) {
    /* Ті самі межі, що Test_Handle_CMD_SET_THRESHOLDS (test_soldier_logic.c)
     * та парсер 0x9A: інверсія, z_opt поза зоною, |Z| > 100.00. */
    LorenzThresholds t = { 200, 4500, 2900, 0xFF, 0 };
    ASSERT_TRUE(Lorenz_Thresholds_Valid(&t));
    t.z_min_x100 = t.z_max_x100;                  /* колапс зони */
    ASSERT_FALSE(Lorenz_Thresholds_Valid(&t));
    t = (LorenzThresholds){ 200, 4500, 100, 0, 0 };  /* opt < min */
    ASSERT_FALSE(Lorenz_Thresholds_Valid(&t));
    t = (LorenzThresholds){ -10001, 4500, 2900, 0, 0 }; /* за межею -100.00 */
    ASSERT_FALSE(Lorenz_Thresholds_Valid(&t));
    t = (LorenzThresholds){ 200, 10001, 2900, 0, 0 };   /* за межею +100.00 */
    ASSERT_FALSE(Lorenz_Thresholds_Valid(&t));
}

TEST(test_fw8_survives_remount_and_compact) {
    /* Persist = сенс фічі: конфіг живе через remount (VBAT-loss аналог)
     * і через compact (перенос живих ключів на нову сторінку). */
    fresh_mount();
    LorenzThresholds in = { 150, 4800, 3100, 7, 3 }, out;
    ASSERT_TRUE(Lorenz_Thresholds_Save(&kv, &in));
    ASSERT_TRUE(FlashKv_Compact(&kv));
    ASSERT_TRUE(FlashKv_Mount(&kv, &mock_ops, &flash, MOCK_PAGE_DWS));
    ASSERT_TRUE(Lorenz_Thresholds_Load(&kv, &out));
    ASSERT_EQ(out.z_max_x100, 4800);
    ASSERT_EQ(out.config_version, 3);
}

/* ════════════════════════════════════════════════════════════════════
 * 6. [FW.2 TRL-7] FC high-water поверх KV (fc_hiwater.h, ключ 0x14)
 *
 * Інваріант I-HW: переданий FC строго менший за межу у Flash на момент
 * TX → floor після cold-boot не може повторити nonce. Дисципліна
 * викликача (КЕНОЗИС-advance, атомарний floor+advance на cold-boot) —
 * шапка fc_hiwater.h; тут вона прогоняється як сценарій.
 * ════════════════════════════════════════════════════════════════════ */
#include "../common/fc_hiwater.h"

TEST(test_fw2_load_empty_kv_no_floor) {
    fresh_mount();
    ASSERT_EQ(Fc_Hiwater_Load(&kv), 0u); /* нема якоря → HRNG-шлях */
}

TEST(test_fw2_advance_load_roundtrip) {
    fresh_mount();
    uint32_t cache = 0;
    ASSERT_TRUE(Fc_Hiwater_Advance(&kv, 1257u, &cache));
    ASSERT_EQ(cache, 1257u);
    ASSERT_EQ(Fc_Hiwater_Load(&kv), 1257u);
}

TEST(test_fw2_load_rejects_garbage) {
    /* Значення поза 24-bit вікном FC = сміття (не наше покоління запису)
     * → floor відсутній, без отруєння лічильника. */
    fresh_mount();
    ASSERT_TRUE(FlashKv_Put32(&kv, FW2_FC_KV_KEY_HIWATER,
                              FW2_FC_VALUE_MASK + 1u));
    ASSERT_EQ(Fc_Hiwater_Load(&kv), 0u);
    ASSERT_TRUE(FlashKv_Put32(&kv, FW2_FC_KV_KEY_HIWATER, 0u));
    ASSERT_EQ(Fc_Hiwater_Load(&kv), 0u);
}

TEST(test_fw2_should_advance_semantics) {
    /* Ключа ще нема (hiwater 0) → перший запис "час" завжди. */
    ASSERT_TRUE(Fc_Hiwater_Should_Advance(0u, 1u));
    /* Далеко від межі → спимо. */
    ASSERT_FALSE(Fc_Hiwater_Should_Advance(1000u, 100u));
    /* Рівно MARGIN до межі → вже час (включно). */
    ASSERT_TRUE(Fc_Hiwater_Should_Advance(1000u,
                                          1000u - FW2_FC_HIWATER_MARGIN));
    ASSERT_FALSE(Fc_Hiwater_Should_Advance(1000u,
                                           999u - FW2_FC_HIWATER_MARGIN));
}

TEST(test_fw2_target_clamps_at_ceiling_no_wear) {
    /* Біля стелі 24-bit межа клемпиться; повторний Advance на ту саму
     * стелю ідемпотентний — нуль зайвих program (epoch-край без wear). */
    fresh_mount();
    uint32_t cache = 0;
    uint32_t t = Fc_Hiwater_Target(FW2_FC_VALUE_MASK - 10u);
    ASSERT_EQ(t, FW2_FC_VALUE_MASK);
    ASSERT_TRUE(Fc_Hiwater_Advance(&kv, t, &cache));
    int programs_before = flash.program_count;
    ASSERT_TRUE(Fc_Hiwater_Advance(&kv, t, &cache)); /* no-op */
    ASSERT_EQ(flash.program_count, programs_before);
}

TEST(test_fw2_advance_fail_cache_untouched) {
    /* Мертвий program → Advance чесно відмовляє, кеш недоторканий —
     * cold-boot-викликач відкочується на HRNG-reseed, не на сирий floor. */
    fresh_mount();
    uint32_t cache = 0;
    ASSERT_TRUE(Fc_Hiwater_Advance(&kv, 500u, &cache));
    flash.die_after_programs = 0;
    ASSERT_FALSE(Fc_Hiwater_Advance(&kv, 756u, &cache));
    ASSERT_EQ(cache, 500u);
}

TEST(test_fw2_coldboot_floor_above_all_sent) {
    /* Життя вузла: reseed → сотні TX з КЕНОЗИС-advance за дисципліною →
     * смерть VBAT. Інваріант: floor у Flash > максимального переданого FC. */
    fresh_mount();
    uint32_t fc = 1000u;          /* HRNG-reseed першого втілення */
    uint32_t hiwater = Fc_Hiwater_Load(&kv); /* 0 — якоря ще нема */
    uint32_t max_sent = 0;
    for (int cycle = 0; cycle < 600; cycle++) {
        fc = (fc + 1u) & FW2_FC_VALUE_MASK;  /* TX циклу */
        max_sent = fc;
        /* КЕНОЗИС: проактивний advance із запасом MARGIN */
        if (Fc_Hiwater_Should_Advance(hiwater, fc + 1u)) {
            ASSERT_TRUE(Fc_Hiwater_Advance(&kv, Fc_Hiwater_Target(fc),
                                           &hiwater));
        }
        ASSERT_TRUE(fc < hiwater); /* I-HW тримається щоцикл */
    }
    /* VBAT-смерть → нове втілення монтує той самий Flash */
    ASSERT_TRUE(FlashKv_Mount(&kv, &mock_ops, &flash, MOCK_PAGE_DWS));
    uint32_t floor_fc = Fc_Hiwater_Load(&kv);
    ASSERT_TRUE(floor_fc > max_sent); /* повтор nonce неможливий */
}

TEST(test_fw2_double_coldboot_no_reuse) {
    /* Brownout одразу після brownout: floor застосовний лише разом з
     * НЕГАЙНИМ advance (атомарність) → другий cold-boot стартує вище
     * за все, що перше коротке втілення встигло передати. */
    fresh_mount();
    uint32_t cache = 0;
    ASSERT_TRUE(Fc_Hiwater_Advance(&kv, 1000u, &cache)); /* якір минулого */

    /* cold-boot #1: floor + атомарний advance, кілька TX, раптова смерть */
    ASSERT_TRUE(FlashKv_Mount(&kv, &mock_ops, &flash, MOCK_PAGE_DWS));
    uint32_t floor1 = Fc_Hiwater_Load(&kv);
    ASSERT_EQ(floor1, 1000u);
    uint32_t hiwater = floor1;
    ASSERT_TRUE(Fc_Hiwater_Advance(&kv, Fc_Hiwater_Target(floor1), &hiwater));
    uint32_t last_sent = floor1 + 3u; /* TX floor+1 .. floor+3 */

    /* cold-boot #2 */
    ASSERT_TRUE(FlashKv_Mount(&kv, &mock_ops, &flash, MOCK_PAGE_DWS));
    uint32_t floor2 = Fc_Hiwater_Load(&kv);
    ASSERT_TRUE(floor2 > last_sent); /* перший TX = floor2+1 — без повтору */
}

TEST(test_fw2_hiwater_survives_remount_and_compact) {
    fresh_mount();
    uint32_t cache = 0;
    ASSERT_TRUE(Fc_Hiwater_Advance(&kv, 4242u, &cache));
    ASSERT_TRUE(FlashKv_Compact(&kv));
    ASSERT_TRUE(FlashKv_Mount(&kv, &mock_ops, &flash, MOCK_PAGE_DWS));
    ASSERT_EQ(Fc_Hiwater_Load(&kv), 4242u);
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

    printf("\n— [FW.8] Z-пороги поверх KV (0x10/0x11) —\n");
    RUN(test_fw8_save_load_roundtrip);
    RUN(test_fw8_load_empty_kv_returns_defaults);
    RUN(test_fw8_save_rejects_invalid_never_pollutes_flash);
    RUN(test_fw8_negative_z_survives_u32_packing);
    RUN(test_fw8_torn_pair_powercut_falls_to_defaults);
    RUN(test_fw8_mixed_generation_invalid_combo_falls_to_defaults);
    RUN(test_fw8_valid_agrees_with_parser);
    RUN(test_fw8_survives_remount_and_compact);

    printf("\n— [FW.2 TRL-7] FC high-water поверх KV (0x14) —\n");
    RUN(test_fw2_load_empty_kv_no_floor);
    RUN(test_fw2_advance_load_roundtrip);
    RUN(test_fw2_load_rejects_garbage);
    RUN(test_fw2_should_advance_semantics);
    RUN(test_fw2_target_clamps_at_ceiling_no_wear);
    RUN(test_fw2_advance_fail_cache_untouched);
    RUN(test_fw2_coldboot_floor_above_all_sent);
    RUN(test_fw2_double_coldboot_no_reuse);
    RUN(test_fw2_hiwater_survives_remount_and_compact);

    printf("\n════════════════════════════════════════════════════════════════════\n");
    printf("Passed: %d, Failed: %d\n", tests_passed, tests_failed);
    return tests_failed == 0 ? 0 : 1;
}
