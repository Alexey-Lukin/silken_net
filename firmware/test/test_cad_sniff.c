// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * test_cad_sniff.c — [ARCH.26 L3] host-тести CAD-нюху + PANIC-преамбули.
 *
 * Пінить контракт ДО bench-фліпу гейта (ARCH26_CAD_ENABLED): роль-гейт
 * (нюх — лише Провідник), каденція на wall-time guard'ах (cold-start /
 * зсув назад), чверть-символьна математика преамбули (мінімальність,
 * floor 8, сатурація 65535), дворівневий Vcap-гейт «останнього зойку»,
 * CadDone→RX seam. Тест №10 — інваріант гарантії T_pre > T_sniff:
 * розсинхрон baseline-пари констант (нюх ↔ преамбула) валить сюїту.
 *
 * Канон: 03_01 §1.9 (драбина L3) + 02_03 §9.10 (double-bind) + 00_07 ARCH.26.
 */
#include <stdio.h>
#include <stdint.h>

#include "../common/cad_sniff.h"

static int tests_passed = 0;
static int tests_failed = 0;

#define ASSERT_TRUE(expr) do { \
    if (expr) { tests_passed++; } \
    else { tests_failed++; \
           printf("  FAIL %s:%d: %s\n", __FILE__, __LINE__, #expr); } \
} while (0)

#define ASSERT_EQ(a, b) ASSERT_TRUE((a) == (b))

/* Airtime преамбули у мкс: T_air(n) = (n + 4.25)·T_sym = (4n+17)·T_sym/4. */
static uint64_t preamble_air_us(uint16_t n, uint32_t t_sym_us)
{
    return ((uint64_t)(4u * (uint32_t)n + 17u) * t_sym_us) / 4u;
}

/* ── Роль-гейт: рядовий Солдат не нюхає ніколи ───────────────────────── */
static void test_sniff_gated_to_provisioner(void)
{
    printf("test_sniff_gated_to_provisioner\n");
    ASSERT_EQ(Cad_Sniff_Due(0u, 1000u, 0u, 3u), 0u);      /* навіть cold-start */
    ASSERT_EQ(Cad_Sniff_Due(0u, 1000u, 1u, 3u), 0u);      /* навіть прострочений */
    ASSERT_EQ(Cad_Sniff_Due(0u, 0xFFFFFFFFu, 1u, 0u), 0u);
}

/* ── Cold-start / SRAM-wipe: маркер 0 → нюхнути зараз ────────────────── */
static void test_sniff_due_on_cold_start(void)
{
    printf("test_sniff_due_on_cold_start\n");
    ASSERT_EQ(Cad_Sniff_Due(1u, 0u, 0u, 3u), 1u);         /* і wall ще 0 */
    ASSERT_EQ(Cad_Sniff_Due(1u, 123456u, 0u, 3u), 1u);
}

/* ── Каденція: межа періоду включно ──────────────────────────────────── */
static void test_sniff_cadence_boundary(void)
{
    printf("test_sniff_cadence_boundary\n");
    ASSERT_EQ(Cad_Sniff_Due(1u, 1002u, 1000u, 3u), 0u);   /* минуло 2 < 3 */
    ASSERT_EQ(Cad_Sniff_Due(1u, 1003u, 1000u, 3u), 1u);   /* рівно період */
    ASSERT_EQ(Cad_Sniff_Due(1u, 1004u, 1000u, 3u), 1u);   /* прострочено */
    ASSERT_EQ(Cad_Sniff_Due(1u, 1000u, 1000u, 0u), 1u);   /* period 0 = щоразу */
}

/* ── Зсув годинника назад (маяк відкотив календар) → не due ──────────── */
static void test_sniff_monotonic_backward(void)
{
    printf("test_sniff_monotonic_backward\n");
    ASSERT_EQ(Cad_Sniff_Due(1u, 999u, 1000u, 3u), 0u);
    ASSERT_EQ(Cad_Sniff_Due(1u, 1u, 0xFFFFFFFEu, 3u), 0u);
}

/* ── Floor: суб-символьні запити падають у дефолт-8 ──────────────────── */
static void test_preamble_min_floor(void)
{
    printf("test_preamble_min_floor\n");
    ASSERT_EQ(Cad_Preamble_Symbols_For_Ms(0u, CAD_T_SYM_SF9_BW125_US), 8u);
    ASSERT_EQ(Cad_Preamble_Symbols_For_Ms(1u, CAD_T_SYM_SF9_BW125_US), 8u);
    ASSERT_EQ(Cad_Preamble_Symbols_For_Ms(17u, CAD_T_SYM_SF9_BW125_US), 8u);
    ASSERT_EQ(Cad_Preamble_Symbols_For_Ms(100u, 0u), 8u);  /* t_sym 0 → захист */
}

/* ── Сатурація на стелі регістра SX126x, без overflow ────────────────── */
static void test_preamble_saturation(void)
{
    printf("test_preamble_saturation\n");
    ASSERT_EQ(Cad_Preamble_Symbols_For_Ms(0xFFFFFFFFu, CAD_T_SYM_SF9_BW125_US), 65535u);
    ASSERT_EQ(Cad_Preamble_Symbols_For_Ms(300000u, CAD_T_SYM_SF9_BW125_US), 65535u);
    /* межа знизу: 65535 симв @SF9 ≈ 268.4 с — 260 с ще ПІД стелею */
    ASSERT_TRUE(Cad_Preamble_Symbols_For_Ms(260000u, CAD_T_SYM_SF9_BW125_US) < 65535u);
}

/* ── Мінімальність: n покриває t_ms, n−1 вже ні (пінить 4.25 + ceil) ─── */
static void test_preamble_covers_airtime(void)
{
    printf("test_preamble_covers_airtime\n");
    const uint32_t cases_ms[] = { 100u, 1000u, 3000u, 4000u, 10000u };
    for (unsigned i = 0; i < sizeof cases_ms / sizeof cases_ms[0]; i++) {
        uint32_t t_ms = cases_ms[i];
        uint16_t n = Cad_Preamble_Symbols_For_Ms(t_ms, CAD_T_SYM_SF9_BW125_US);
        ASSERT_TRUE(preamble_air_us(n, CAD_T_SYM_SF9_BW125_US) >= (uint64_t)t_ms * 1000u);
        ASSERT_TRUE(preamble_air_us((uint16_t)(n - 1u), CAD_T_SYM_SF9_BW125_US)
                    < (uint64_t)t_ms * 1000u);
    }
    /* конкретика baseline: 4000 мс @SF9 → 973 симв (канон 02_03 §9.10) */
    ASSERT_EQ(Cad_Preamble_Symbols_For_Ms(4000u, CAD_T_SYM_SF9_BW125_US), 973u);
}

/* ── Дворівневий Vcap-гейт «останнього зойку» ────────────────────────── */
static void test_panic_preamble_two_tier(void)
{
    printf("test_panic_preamble_two_tier\n");
    ASSERT_EQ(Cad_Panic_Preamble_Symbols(4500u, CAD_PANIC_PREAMBLE_VCAP_MIN_MV, 973u), 973u);
    ASSERT_EQ(Cad_Panic_Preamble_Symbols(5200u, CAD_PANIC_PREAMBLE_VCAP_MIN_MV, 973u), 973u);
    ASSERT_EQ(Cad_Panic_Preamble_Symbols(4499u, CAD_PANIC_PREAMBLE_VCAP_MIN_MV, 973u), 8u);
    /* до FW.50 тракт бачить VDDA ≈3300 (і EMA=0 на cold-boot) → fail-closed */
    ASSERT_EQ(Cad_Panic_Preamble_Symbols(3300u, CAD_PANIC_PREAMBLE_VCAP_MIN_MV, 973u), 8u);
    ASSERT_EQ(Cad_Panic_Preamble_Symbols(0u,    CAD_PANIC_PREAMBLE_VCAP_MIN_MV, 973u), 8u);
}

/* ── CadDone→RX seam ─────────────────────────────────────────────────── */
static void test_should_open_rx(void)
{
    printf("test_should_open_rx\n");
    ASSERT_EQ(Cad_Should_Open_Rx(1u), 1u);
    ASSERT_EQ(Cad_Should_Open_Rx(0u), 0u);
    ASSERT_EQ(Cad_Should_Open_Rx(0xFFu), 1u);   /* будь-яке ненульове = активність */
}

/* ── Інваріант гарантії: baseline-преамбула ПЕРЕЖИВАЄ період нюху ────── */
static void test_panic_preamble_outlasts_sniff_period(void)
{
    printf("test_panic_preamble_outlasts_sniff_period\n");
    uint16_t n = Cad_Preamble_Symbols_For_Ms(CAD_PANIC_PREAMBLE_MS,
                                             CAD_T_SYM_SF9_BW125_US);
    /* T_pre > T_sniff: інакше нюх Провідника між преамбулами промахнеться —
       міняєш одну константу пари, міняй і другу (02_03 §9.10) */
    ASSERT_TRUE(preamble_air_us(n, CAD_T_SYM_SF9_BW125_US) >
                (uint64_t)CAD_SNIFF_PERIOD_S_DEFAULT * 1000000u);
}

int main(void)
{
    printf("── test_cad_sniff: ARCH.26 L3 CAD-нюх + PANIC-преамбула ──\n");

    test_sniff_gated_to_provisioner();
    test_sniff_due_on_cold_start();
    test_sniff_cadence_boundary();
    test_sniff_monotonic_backward();
    test_preamble_min_floor();
    test_preamble_saturation();
    test_preamble_covers_airtime();
    test_panic_preamble_two_tier();
    test_should_open_rx();
    test_panic_preamble_outlasts_sniff_period();

    printf("──────────────────────────────────────────────────────────\n");
    printf("PASS: %d  FAIL: %d\n", tests_passed, tests_failed);
    return tests_failed != 0;
}
