// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * test_voc_maxhold.c — [HW.19] max-hold V_OC у MPPT-вікні BQ25570 (host).
 *
 * Прилад — синтетичний `VIN_DC`: робоча точка ROC×V_OC весь час, крім
 * 256-мс відкритого вікна кожні 16 с, де стоїть V_OC (02_03 §3.2). Тести
 * судять АРИФМЕТИКУ вікна, не фізику: (а) за будь-якої фази MPPT-вікна
 * відносно старту збору max-hold віддає V_OC — інваріант, заради якого
 * існують обидві сталі (вікно ≥ період + відкрите; крок ≤ половини
 * відкритого); (б) розрив у зразках чи час назад дають сентинел «не
 * виміряно», а не робочу точку під виглядом V_OC; (в) межі точні
 * (крок 128 приймається, 129 — ні; DONE рівно на window_ms).
 *
 * Build: make -C firmware/test voc_maxhold
 */
#include <stdio.h>
#include <stdint.h>

#include "../common/voc_maxhold.h"
#include "../common/lora_ccm.h"   /* [FW.66] сентинел байтів 16..17 wire-rev2.2 */

static int tests_passed = 0;
static int tests_failed = 0;

static int last_failed = 0;
#define RUN(name) do { \
    last_failed = 0; \
    printf("  %-58s", #name); \
    name(); \
    if (!last_failed) { printf(" ✅\n"); tests_passed++; } \
} while(0)

#define FAILF(fmt, ...) do { \
    printf(" ❌ FAIL (line %d: " fmt ")\n", __LINE__, __VA_ARGS__); \
    tests_failed++; last_failed = 1; return; \
} while(0)

#define ASSERT_EQ(a, b) do { \
    long long _a = (long long)(a), _b = (long long)(b); \
    if (_a != _b) FAILF("got %lld, expected %lld", _a, _b); \
} while(0)

/* Синтетичний `VIN_DC`, мВ: V_OC у відкритому вікні, робоча точка поза ним.
 * phase_ms зсуває MPPT-цикл відносно t = 0. */
#define VOC_MV        800u
#define VOC_ROC_MV    520u   /* 0.65 · V_OC — робоча точка §4.А */

static uint16_t Vin_Dc_Mv(uint32_t t_ms, uint32_t phase_ms)
{
    uint32_t in_cycle = (t_ms + VOC_MPPT_PERIOD_MS - (phase_ms % VOC_MPPT_PERIOD_MS))
                        % VOC_MPPT_PERIOD_MS;
    return (in_cycle < VOC_MPPT_OPEN_MS) ? VOC_MV : VOC_ROC_MV;
}

/* Збір із кроком step_ms до DONE; повертає момент DONE (або 0, якщо збій). */
static uint32_t Collect(VocMaxHold *s, uint32_t phase_ms, uint32_t step_ms, int *last_rc)
{
    uint32_t t = 0u;
    for (;;) {
        int rc = Voc_MaxHold_Feed(s, t, Vin_Dc_Mv(t, phase_ms));
        *last_rc = rc;
        if (rc == VOC_MAXHOLD_DONE) return t;
        if (rc < 0) return 0u;
        t += step_ms;
        if (t > 60000u) return 0u;   /* запобіжник проти нескінченного циклу */
    }
}

static void test_init_rejects_window_below_minimum(void)
{
    VocMaxHold s;
    ASSERT_EQ(Voc_MaxHold_Init(&s, VOC_MAXHOLD_WINDOW_MIN_MS - 1u), VOC_MAXHOLD_ERR_WINDOW);
    ASSERT_EQ(Voc_MaxHold_Feed(&s, 0u, VOC_MV), VOC_MAXHOLD_ERR_GAP);   /* зіпсовано назавжди */
    ASSERT_EQ(Voc_MaxHold_Result(&s), VOC_MV_UNKNOWN);
    ASSERT_EQ(Voc_MaxHold_Init(&s, VOC_MAXHOLD_WINDOW_MIN_MS), VOC_MAXHOLD_PENDING);
}

static void test_any_phase_yields_voc_at_max_step(void)
{
    /* Інваріант обох сталих: вікно ≥ період + відкрите, крок = стеля →
     * за КОЖНОЇ фази MPPT-вікна max-hold бачить V_OC. */
    for (uint32_t phase = 0u; phase < VOC_MPPT_PERIOD_MS; phase += 37u) {
        VocMaxHold s;
        int rc = 0;
        Voc_MaxHold_Init(&s, VOC_MAXHOLD_WINDOW_MIN_MS);
        uint32_t done_at = Collect(&s, phase, VOC_MAXHOLD_STEP_MAX_MS, &rc);
        if (rc != VOC_MAXHOLD_DONE) FAILF("phase %u: rc %d", (unsigned)phase, rc);
        if (done_at < VOC_MAXHOLD_WINDOW_MIN_MS) FAILF("phase %u: DONE at %u", (unsigned)phase, (unsigned)done_at);
        if (Voc_MaxHold_Result(&s) != VOC_MV) FAILF("phase %u: got %u mV", (unsigned)phase, (unsigned)Voc_MaxHold_Result(&s));
    }
}

static void test_done_exactly_at_window_and_final(void)
{
    VocMaxHold s;
    Voc_MaxHold_Init(&s, VOC_MAXHOLD_WINDOW_MIN_MS);
    for (uint32_t t = 0u; t < VOC_MAXHOLD_WINDOW_MIN_MS; t += 100u) {
        ASSERT_EQ(Voc_MaxHold_Feed(&s, t, VOC_ROC_MV), VOC_MAXHOLD_PENDING);
        ASSERT_EQ(Voc_MaxHold_Result(&s), VOC_MV_UNKNOWN);   /* до DONE — лише сентинел */
    }
    ASSERT_EQ(Voc_MaxHold_Feed(&s, VOC_MAXHOLD_WINDOW_MIN_MS, VOC_MV), VOC_MAXHOLD_DONE);
    ASSERT_EQ(Voc_MaxHold_Result(&s), VOC_MV);
    /* Після DONE — знімок: вищий зразок пізніше результату не рухає. */
    ASSERT_EQ(Voc_MaxHold_Feed(&s, VOC_MAXHOLD_WINDOW_MIN_MS + 50u, 999u), VOC_MAXHOLD_DONE);
    ASSERT_EQ(Voc_MaxHold_Result(&s), VOC_MV);
}

static void test_gap_boundary_128_ok_129_spoils(void)
{
    VocMaxHold ok, bad;
    Voc_MaxHold_Init(&ok, VOC_MAXHOLD_WINDOW_MIN_MS);
    Voc_MaxHold_Feed(&ok, 0u, VOC_ROC_MV);
    ASSERT_EQ(Voc_MaxHold_Feed(&ok, VOC_MAXHOLD_STEP_MAX_MS, VOC_ROC_MV), VOC_MAXHOLD_PENDING);

    Voc_MaxHold_Init(&bad, VOC_MAXHOLD_WINDOW_MIN_MS);
    Voc_MaxHold_Feed(&bad, 0u, VOC_ROC_MV);
    ASSERT_EQ(Voc_MaxHold_Feed(&bad, VOC_MAXHOLD_STEP_MAX_MS + 1u, VOC_ROC_MV), VOC_MAXHOLD_ERR_GAP);
    ASSERT_EQ(Voc_MaxHold_Result(&bad), VOC_MV_UNKNOWN);
}

static void test_gap_spoils_even_if_window_was_caught(void)
{
    /* Вікно V_OC зразок таки побачив, але потім був розрив: результат усе
     * одно сентинел — судиться щільність збору, не удача. */
    VocMaxHold s;
    Voc_MaxHold_Init(&s, VOC_MAXHOLD_WINDOW_MIN_MS);
    Voc_MaxHold_Feed(&s, 0u, VOC_MV);        /* фаза 0: перший зразок у вікні */
    Voc_MaxHold_Feed(&s, 100u, VOC_MV);
    ASSERT_EQ(Voc_MaxHold_Feed(&s, 400u, VOC_ROC_MV), VOC_MAXHOLD_ERR_GAP);
    ASSERT_EQ(Voc_MaxHold_Result(&s), VOC_MV_UNKNOWN);
    for (uint32_t t = 500u; t <= VOC_MAXHOLD_WINDOW_MIN_MS + 500u; t += 100u)
        ASSERT_EQ(Voc_MaxHold_Feed(&s, t, VOC_MV), VOC_MAXHOLD_ERR_GAP);   /* лишається зіпсованим */
    ASSERT_EQ(Voc_MaxHold_Result(&s), VOC_MV_UNKNOWN);
}

static void test_time_backwards_spoils(void)
{
    VocMaxHold s;
    Voc_MaxHold_Init(&s, VOC_MAXHOLD_WINDOW_MIN_MS);
    Voc_MaxHold_Feed(&s, 1000u, VOC_ROC_MV);
    ASSERT_EQ(Voc_MaxHold_Feed(&s, 999u, VOC_MV), VOC_MAXHOLD_ERR_TIME);
    ASSERT_EQ(Voc_MaxHold_Result(&s), VOC_MV_UNKNOWN);
}

/* [FW.66 · wire-rev2.2] Байти 16..17 CCM-кадру: «не виміряно» — той самий нуль, що дає
 * семплер, і бекенд читає його так само (ніколи не «нуль вольт»). */
static void test_ccm_voc_unknown_mirrors_sampler(void)
{
    ASSERT_EQ(FW2_VOC_MV_UNKNOWN, VOC_MV_UNKNOWN);
}

static void test_zero_mv_reads_as_floor_not_sentinel(void)
{
    /* Мертве джерело (0 мВ увесь час) — це ВИМІР, і він не сміє злитися з
     * сентинелом «не виміряно». */
    VocMaxHold s;
    int rc = VOC_MAXHOLD_PENDING;
    Voc_MaxHold_Init(&s, VOC_MAXHOLD_WINDOW_MIN_MS);
    for (uint32_t t = 0u; rc == VOC_MAXHOLD_PENDING; t += 100u)
        rc = Voc_MaxHold_Feed(&s, t, 0u);
    ASSERT_EQ(rc, VOC_MAXHOLD_DONE);
    ASSERT_EQ(Voc_MaxHold_Result(&s), VOC_MV_MIN);
}

static void test_sample_counter_saturates(void)
{
    VocMaxHold s;
    int rc = VOC_MAXHOLD_PENDING;
    Voc_MaxHold_Init(&s, 100000u);            /* довге вікно, крок 1 мс → > 65535 зразків */
    for (uint32_t t = 0u; rc == VOC_MAXHOLD_PENDING; t += 1u)
        rc = Voc_MaxHold_Feed(&s, t, VOC_ROC_MV);
    ASSERT_EQ(rc, VOC_MAXHOLD_DONE);
    ASSERT_EQ(s.samples, UINT16_MAX);         /* сатурація, не wrap до малого числа */
    ASSERT_EQ(Voc_MaxHold_Result(&s), VOC_ROC_MV);
}

int main(void)
{
    printf("[HW.19] voc_maxhold — max-hold V_OC у MPPT-вікні BQ25570 (host)\n");
    RUN(test_init_rejects_window_below_minimum);
    RUN(test_any_phase_yields_voc_at_max_step);
    RUN(test_done_exactly_at_window_and_final);
    RUN(test_gap_boundary_128_ok_129_spoils);
    RUN(test_gap_spoils_even_if_window_was_caught);
    RUN(test_time_backwards_spoils);
    RUN(test_zero_mv_reads_as_floor_not_sentinel);
    RUN(test_ccm_voc_unknown_mirrors_sampler);
    RUN(test_sample_counter_saturates);
    printf("\n%d passed, %d failed\n", tests_passed, tests_failed);
    return tests_failed == 0 ? 0 : 1;
}
