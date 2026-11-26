// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * test_pot_dendro.c — [FW.70] host-тести потенціометричного датчика дендрометра пілота П3.
 *
 * Мок PotDendroOps пише журнал подій (ключ · затримка · блок каналу) і віддає суми, які задав
 * тест (дві половини збудження — окремо). Доводить: порядок «ключ → затримка → половина
 * збудження → повзунок → половина збудження → ключ вимкнено»; ключ вимикається на КОЖНІЙ гілці
 * збою; частка скорочує падіння на ключі (той самий повзунок за різного збудження — той самий
 * показ) і лінійне просідання живлення за час виміру; показ ніколи не стає сентинелом журналу.
 *
 * Build: make -C firmware/test pot_dendro
 */
#include <stdio.h>
#include <stdint.h>
#include <string.h>

#include "../common/pot_dendro.h"
#include "../common/logger_journal.h"

static int tests_passed = 0;
static int tests_failed = 0;

#define TEST(name) static void name(void)
#define RUN(name) do { \
    int _f = tests_failed; \
    printf("  %-58s", #name); \
    name(); \
    if (tests_failed == _f) { printf(" ✅\n"); tests_passed++; } \
} while (0)

#define ASSERT_EQ(a, b) do { \
    long long _a = (long long)(a), _b = (long long)(b); \
    if (_a != _b) { \
        printf(" ❌ FAIL (line %d: got %lld, expected %lld)\n", __LINE__, _a, _b); \
        tests_failed++; return; \
    } \
} while (0)
#define ASSERT_TRUE(e) ASSERT_EQ(!!(e), 1)
#define ASSERT_STR(a, b) do { \
    if (strcmp((a), (b)) != 0) { \
        printf(" ❌ FAIL (line %d: got \"%s\", expected \"%s\")\n", __LINE__, (a), (b)); \
        tests_failed++; return; \
    } \
} while (0)

/* ── мок: середній відлік на вибірку (×n), відмова виклику, журнал подій ── */
static uint32_t EXC_FIRST, EXC_SECOND, WIPER;   /* відлік на вибірку: половини збудження, повзунок */
static int      FAIL_CALL;                      /* -1 — ніколи; інакше номер виклику adc_sum (0…2) */
static int      CALLS, EXC_CALLS;
static int      POWER;
static char     LOG[256];

static void logc(const char *s) { strncat(LOG, s, sizeof LOG - strlen(LOG) - 1); }
static void m_power(void *io, int on) { (void)io; POWER = on; logc(on ? "P1 " : "P0 "); }
static void m_delay(void *io, uint32_t ms) { (void)io; char b[16]; snprintf(b, sizeof b, "D%u ", (unsigned)ms); logc(b); }
static int  m_sum(void *io, uint8_t ch, uint16_t n, uint32_t *sum)
{
    (void)io;
    char b[16];
    snprintf(b, sizeof b, "%c%u%s ", ch == POT_CH_EXCITE ? 'E' : 'W', (unsigned)n, POWER ? "" : "!");
    logc(b);
    if (CALLS++ == FAIL_CALL) return 0;   /* відмова: *sum не пише (контракт шва) */
    uint32_t per = (ch == POT_CH_WIPER) ? WIPER : (EXC_CALLS++ == 0 ? EXC_FIRST : EXC_SECOND);
    *sum = per * n;
    return 1;
}
static const PotDendroOps OPS = { m_power, m_delay, m_sum };

static void mock2(uint32_t exc_first, uint32_t exc_second, uint32_t wiper, int fail_call)
{
    EXC_FIRST = exc_first; EXC_SECOND = exc_second; WIPER = wiper;
    FAIL_CALL = fail_call; CALLS = 0; EXC_CALLS = 0; POWER = 0; LOG[0] = '\0';
}
static void mock(uint32_t exc, uint32_t wiper, int fail_call) { mock2(exc, exc, wiper, fail_call); }

TEST(test_scale_and_sentinels_fit_the_journal)
{
    ASSERT_EQ(POT_DENDRO_NONE, LOGJ_READING_NONE);
    ASSERT_TRUE(POT_DENDRO_FULL < LOGJ_READING_CLOSED);
    ASSERT_EQ(POT_DENDRO_FULL, 4095u * 16u);   /* та сама шкала, що журнал чекає від «12 біт × 16» */
}

TEST(test_sequence_brackets_the_wiper_with_two_halves_of_excitation)
{
    PotDendroReading r;
    mock(4000, 1000, -1);
    PotDendro_Sense(&OPS, NULL, &r);
    ASSERT_STR(LOG, "P1 D2 E128 W256 E128 P0 ");   /* усі блоки — під увімкненим ключем */
    ASSERT_EQ(POWER, 0);
    ASSERT_EQ(r.rc, POT_OK);
    ASSERT_EQ(r.exc_sum, 4000u * 256u);
    ASSERT_EQ(r.wiper_sum, 1000u * 256u);
    ASSERT_EQ(r.reading, 16380);                   /* ¼ ходу → ¼ шкали */
}

TEST(test_ratio_cancels_the_drop_on_the_excitation_switch)
{
    /* Той самий повзунок (30 % доріжки), а верх доріжки — то 4000, то 3800 відліків (ключ GPIO
     * просів): напруга повзунка інша, показ — той самий. Показ повзунка проти VDDA (×16) розійшовся
     * б на 960 відліків — ≈ 150 мкм на ході 10 мм. */
    PotDendroReading a, b;
    mock(4000, 1200, -1);  PotDendro_Sense(&OPS, NULL, &a);
    mock(3800, 1140, -1);  PotDendro_Sense(&OPS, NULL, &b);
    ASSERT_EQ(a.rc, POT_OK);
    ASSERT_EQ(b.rc, POT_OK);
    ASSERT_EQ(a.reading, 19656);   /* 0.3 × 65520 */
    ASSERT_EQ(b.reading, a.reading);
    ASSERT_EQ(1200 * 16 - 1140 * 16, 960);
}

TEST(test_linear_supply_sag_during_the_measurement_cancels)
{
    /* Живлення лінійно сідає за час виміру: перша половина збудження бачить 4020, друга — 3980,
     * повзунок (30 %) — посередині, при 4000. Центри сум збігаються → показ той самий, що без
     * просідання. Збудження одним блоком ДО повзунка дало б 4020 і зсув ≈ 0.5 % показу. Мок віддає
     * значення за порядком виклику, не за часом: цей тест пінить арифметику половин, а порядок
     * «половина — повзунок — половина» — test_sequence_brackets_the_wiper_with_two_halves_of_excitation. */
    PotDendroReading r;
    mock2(4020, 3980, 1200, -1);
    PotDendro_Sense(&OPS, NULL, &r);
    ASSERT_EQ(r.rc, POT_OK);
    ASSERT_EQ(r.exc_sum, 4000u * 256u);
    ASSERT_EQ(r.reading, 19656);
}

TEST(test_ends_of_the_track)
{
    PotDendroReading r;
    mock(4000, 0, -1);     PotDendro_Sense(&OPS, NULL, &r);
    ASSERT_EQ(r.reading, 0);
    mock(4000, 4000, -1);  PotDendro_Sense(&OPS, NULL, &r);
    ASSERT_EQ(r.reading, POT_DENDRO_FULL);
    mock(4000, 4000 + POT_DENDRO_OVER_LSB, -1);   /* шум біля верху — межа допуску */
    PotDendro_Sense(&OPS, NULL, &r);
    ASSERT_EQ(r.rc, POT_OK);
    ASSERT_EQ(r.reading, POT_DENDRO_FULL);
}

TEST(test_adc_failure_on_first_half_skips_the_rest_and_powers_off)
{
    PotDendroReading r;
    mock(4000, 1000, 0);
    PotDendro_Sense(&OPS, NULL, &r);
    ASSERT_STR(LOG, "P1 D2 E128 P0 ");
    ASSERT_EQ(r.rc, POT_ERR_ADC);
    ASSERT_EQ(r.reading, POT_DENDRO_NONE);
    ASSERT_EQ(r.exc_sum, 0);
    ASSERT_EQ(r.wiper_sum, 0);
}

TEST(test_adc_failure_on_wiper_powers_off_and_reads_none)
{
    PotDendroReading r;
    mock(4000, 1000, 1);
    PotDendro_Sense(&OPS, NULL, &r);
    ASSERT_STR(LOG, "P1 D2 E128 W256 P0 ");
    ASSERT_EQ(r.rc, POT_ERR_ADC);
    ASSERT_EQ(r.reading, POT_DENDRO_NONE);
    ASSERT_EQ(r.exc_sum, 0);                       /* одна половина — не сума збудження */
    ASSERT_EQ(r.wiper_sum, 0);
}

TEST(test_adc_failure_on_second_half_keeps_wiper_drops_excitation)
{
    PotDendroReading r;
    mock(4000, 1000, 2);
    PotDendro_Sense(&OPS, NULL, &r);
    ASSERT_STR(LOG, "P1 D2 E128 W256 E128 P0 ");
    ASSERT_EQ(r.rc, POT_ERR_ADC);
    ASSERT_EQ(r.reading, POT_DENDRO_NONE);
    ASSERT_EQ(r.exc_sum, 0);
    ASSERT_EQ(r.wiper_sum, 1000u * 256u);          /* прочитаний канал лишається для стенда */
}

TEST(test_low_excitation_is_a_fault_not_a_reading)
{
    PotDendroReading r;
    mock(3071, 1000, -1);  PotDendro_Sense(&OPS, NULL, &r);   /* ключ не тягне чи верх на землі */
    ASSERT_EQ(r.rc, POT_ERR_EXCITE);
    ASSERT_EQ(r.reading, POT_DENDRO_NONE);
    ASSERT_EQ(POWER, 0);
    mock(3072, 1000, -1);  PotDendro_Sense(&OPS, NULL, &r);   /* поріг — ще вимір */
    ASSERT_EQ(r.rc, POT_OK);
}

TEST(test_swapped_sense_and_wiper_inputs_fault_below_the_very_top)
{
    /* PB3/PB4 — сусідні піни гребінки: переплутані, вони дають «збудження» = повзунок і «повзунок»
     * = верх доріжки. Нижче ¾ ходу — −2, у верхній чверті — −3; число дає лише самий верх, де
     * повзунок і верх доріжки збігаються (стеля шкали — її видно в рядку). */
    PotDendroReading r;
    for (uint32_t x = 0; x <= 4000; x += 250) {
        mock(x, 4000, -1);
        PotDendro_Sense(&OPS, NULL, &r);
        if (x < 3072) ASSERT_EQ(r.rc, POT_ERR_EXCITE);
        else if (4000 > x + POT_DENDRO_OVER_LSB) ASSERT_EQ(r.rc, POT_ERR_RANGE);
        ASSERT_TRUE(r.rc != POT_OK || x + POT_DENDRO_OVER_LSB >= 4000);
    }
}

TEST(test_wiper_above_excitation_is_a_wiring_fault)
{
    PotDendroReading r;
    mock(3500, 3500 + POT_DENDRO_OVER_LSB + 1, -1);
    PotDendro_Sense(&OPS, NULL, &r);
    ASSERT_EQ(r.rc, POT_ERR_RANGE);
    ASSERT_EQ(r.reading, POT_DENDRO_NONE);
    ASSERT_EQ(POWER, 0);
}

TEST(test_reading_never_reaches_a_journal_sentinel)
{
    PotDendroReading r;
    for (uint32_t e = 3072; e <= 4095; e += 31)
        for (uint32_t w = 0; w <= e + POT_DENDRO_OVER_LSB; w += 17) {
            mock(e, w, -1);
            PotDendro_Sense(&OPS, NULL, &r);
            ASSERT_EQ(r.rc, POT_OK);
            ASSERT_TRUE(r.reading <= POT_DENDRO_FULL);
        }
}

int main(void)
{
    printf("\n[FW.70] pot_dendro — потенціометричний датчик дендрометра П3\n");
    RUN(test_scale_and_sentinels_fit_the_journal);
    RUN(test_sequence_brackets_the_wiper_with_two_halves_of_excitation);
    RUN(test_ratio_cancels_the_drop_on_the_excitation_switch);
    RUN(test_linear_supply_sag_during_the_measurement_cancels);
    RUN(test_ends_of_the_track);
    RUN(test_adc_failure_on_first_half_skips_the_rest_and_powers_off);
    RUN(test_adc_failure_on_wiper_powers_off_and_reads_none);
    RUN(test_adc_failure_on_second_half_keeps_wiper_drops_excitation);
    RUN(test_low_excitation_is_a_fault_not_a_reading);
    RUN(test_swapped_sense_and_wiper_inputs_fault_below_the_very_top);
    RUN(test_wiper_above_excitation_is_a_wiring_fault);
    RUN(test_reading_never_reaches_a_journal_sentinel);
    printf("\n  %d passed, %d failed\n\n", tests_passed, tests_failed);
    return tests_failed ? 1 : 0;
}
