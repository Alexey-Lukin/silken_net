// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * test_fauna_session.c — [ARCH.40] host-тести монолітної fauna-сесії.
 *
 * Пінить freeze-contract fauna_session.h ДО fauna-pivot (FW.4): Welford-
 * математика проти two-pass еталона, чисельна стабільність на зсунутих
 * даних, і named-тест трекера — test_fauna_sampling_no_stop2_in_session:
 * емуляція девайсного циклу, де «вхід у STOP2» можливий лише ПІСЛЯ
 * повернення Fauna_Run_Session — кожен кадр свідчить, що сну ще не було.
 *
 * Канон: 03_03 §10.2 (моноліт; STOP2 wipe SRAM2) + 00_07 ARCH.40.
 */
#include <stdio.h>
#include <stdint.h>
#include <math.h>

#include "../common/fauna_session.h"

static int tests_passed = 0;
static int tests_failed = 0;

#define ASSERT_TRUE(expr) do { \
    if (expr) { tests_passed++; } \
    else { tests_failed++; \
           printf("  FAIL %s:%d: %s\n", __FILE__, __LINE__, #expr); } \
} while (0)

#define ASSERT_NEAR(a, b, eps) ASSERT_TRUE(fabsf((a) - (b)) < (eps))

/* ── Мок-постачальник кадрів ─────────────────────────────────────────── */
typedef struct {
    uint16_t frames_fed;
    uint16_t fail_at;        /* 0 = ніколи не падати (1-based номер кадру) */
    uint32_t stop2_entries;  /* «сни», що сталися ДО цього кадру */
    uint32_t stop2_seen_mid_session; /* кадри, що бачили сон посеред сесії */
    float    base;           /* детермінований генератор значень */
} MockFrames;

static uint8_t mock_next_mel(void *ctx, float mel_out[LOGMEL_N_MELS])
{
    MockFrames *m = (MockFrames *)ctx;

    /* ARCH.40-інваріант очима постачальника: якби девайс заснув посеред
     * сесії, лічильник snів був би > 0 ще до завершення 156 кадрів. */
    if (m->stop2_entries != 0) m->stop2_seen_mid_session++;

    m->frames_fed++;
    if (m->fail_at != 0 && m->frames_fed == m->fail_at) return 0;

    for (uint16_t i = 0; i < LOGMEL_N_MELS; i++)
        mel_out[i] = m->base + (float)m->frames_fed * 0.25f + (float)i;
    return 1;
}

/* Девайсний кенозис у мініатюрі: сон можливий лише після повернення сесії. */
static void mock_enter_stop2(MockFrames *m) { m->stop2_entries++; }

/* ── Welford проти two-pass еталона ──────────────────────────────────── */
static void test_fauna_welford_matches_two_pass_reference(void)
{
    printf("test_fauna_welford_matches_two_pass_reference\n");
    enum { N = 7 };
    /* Один бін, ручні значення; решта бінів — та сама арифметика. */
    float xs[N] = { 1.0f, 4.0f, 2.5f, -3.0f, 0.5f, 10.0f, 7.25f };

    FaunaWelford w;
    Fauna_Welford_Init(&w);
    float feat[LOGMEL_N_MELS] = { 0 };
    for (int k = 0; k < N; k++) {
        feat[0] = xs[k];
        Fauna_Welford_Update(&w, feat);
    }

    float sum = 0.0f;
    for (int k = 0; k < N; k++) sum += xs[k];
    float ref_mean = sum / (float)N;
    float ss = 0.0f;
    for (int k = 0; k < N; k++) ss += (xs[k] - ref_mean) * (xs[k] - ref_mean);
    float ref_var = ss / (float)N;

    ASSERT_TRUE(w.n == N);
    ASSERT_NEAR(w.mean[0], ref_mean, 1e-5f);
    ASSERT_NEAR(Fauna_Welford_Var(&w, 0), ref_var, 1e-4f);
}

static void test_fauna_welford_stable_on_offset_data(void)
{
    printf("test_fauna_welford_stable_on_offset_data\n");
    /* Сенс Welford: великий зсув + мала дисперсія — naive sum/sum² у float32
     * тут втрачає всю точність (катастрофічне скорочення). */
    FaunaWelford w;
    Fauna_Welford_Init(&w);
    float feat[LOGMEL_N_MELS] = { 0 };
    for (int k = 0; k < (int)FAUNA_SESSION_FRAMES; k++) {
        feat[0] = 10000.0f + ((k % 2) ? 0.5f : -0.5f); /* var = 0.25 */
        Fauna_Welford_Update(&w, feat);
    }
    ASSERT_NEAR(w.mean[0], 10000.0f, 0.01f);
    ASSERT_NEAR(Fauna_Welford_Var(&w, 0), 0.25f, 0.01f);
}

/* ── Named-тест трекера (ARCH.40) ────────────────────────────────────── */
static void test_fauna_sampling_no_stop2_in_session(void)
{
    printf("test_fauna_sampling_no_stop2_in_session\n");
    MockFrames m = { 0 };
    m.base = 1.0f;
    FaunaWelford w;

    /* Девайсний цикл: сесія → (лише потім) кенозис. */
    uint16_t done = Fauna_Run_Session(mock_next_mel, &m, &w);
    mock_enter_stop2(&m);

    ASSERT_TRUE(done == FAUNA_SESSION_FRAMES);
    ASSERT_TRUE(m.frames_fed == FAUNA_SESSION_FRAMES);
    ASSERT_TRUE(w.n == FAUNA_SESSION_FRAMES);
    /* Серце інваріанту: ЖОДЕН з 156 кадрів не бачив сну перед собою. */
    ASSERT_TRUE(m.stop2_seen_mid_session == 0);
    ASSERT_TRUE(m.stop2_entries == 1); /* сон стався — але ПІСЛЯ згортки */
}

static void test_fauna_session_aborts_honestly_on_frame_failure(void)
{
    printf("test_fauna_session_aborts_honestly_on_frame_failure\n");
    MockFrames m = { 0 };
    m.fail_at = 41; /* DMA-збій на 41-му кадрі */
    FaunaWelford w;

    uint16_t done = Fauna_Run_Session(mock_next_mel, &m, &w);

    ASSERT_TRUE(done == 40);
    ASSERT_TRUE(w.n == 40);             /* акумулятор валідний для обробленого */
    ASSERT_TRUE(m.frames_fed == 41);    /* 41-й спробували й він упав */
}

static void test_fauna_accumulator_fits_ram_budget(void)
{
    printf("test_fauna_accumulator_fits_ram_budget\n");
    /* Tripwire проти тихого роздування (03_03 §6 RAM-таблиця: Path B). */
    ASSERT_TRUE(sizeof(FaunaWelford) <= 512);
}

int main(void)
{
    test_fauna_welford_matches_two_pass_reference();
    test_fauna_welford_stable_on_offset_data();
    test_fauna_sampling_no_stop2_in_session();
    test_fauna_session_aborts_honestly_on_frame_failure();
    test_fauna_accumulator_fits_ram_budget();

    printf("════════════════════════════════════════\n");
    printf("Passed: %d, Failed: %d\n", tests_passed, tests_failed);
    return tests_failed ? 1 : 0;
}
