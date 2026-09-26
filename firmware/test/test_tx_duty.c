// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * test_tx_duty.c — [FW.61] лімітер робочого циклу TX Королеви (≤ 1 % / година).
 *
 * Головний пін — ВЛАСТИВІСТЬ, а не приклад: жадібний відправник дванадцять
 * годин стукає в лімітер щосекунди, і після КОЖНОГО дозволеного кадру точна
 * сума ефіру за останню годину (з власного журналу тесту, не з лімітера) не
 * перевищує 36 с. Дзеркальний пін — невакуумність: лімітер, що не пускає
 * нічого, пройшов би першу перевірку зеленим, тож окремо вимірюємо, що
 * пропускна здатність не нижча за чесну (бюджет мінус резерв маяка, за
 * вирахуванням 5-хв запасу кошика).
 *
 * Збірка/прогін: make -C firmware/test tx_duty
 */

#include <stdio.h>
#include <stdint.h>

#include "../queen/tx_duty.h"

static int g_tests_run = 0;
static int g_tests_failed = 0;

#define ASSERT_EQ(actual, expected) do { \
    long long a_ = (long long)(actual); \
    long long e_ = (long long)(expected); \
    g_tests_run++; \
    if (a_ != e_) { \
        printf("  FAIL %s:%d — %s: отримано %lld, очікувано %lld\n", \
               __FILE__, __LINE__, #actual, a_, e_); \
        g_tests_failed++; \
    } \
} while (0)

#define ASSERT_TRUE(cond) ASSERT_EQ(!!(cond), 1)

/* Ефір 16-Б кадру @ SF9 — те, що віддає драйвер (`Lora_Phy_Time_On_Air_Ms`);
 * лімітеру число байдуже, тест бере реальне, щоб лічба кадрів була впізнавана. */
#define AIR16 165u

#define MIN_MS (60u * 1000u)

static unsigned send_greedy(TxDutyLedger *l, uint32_t now, TxDutyClass cls, unsigned max)
{
    unsigned n = 0;
    while (n < max && Tx_Duty_Allows(l, now, AIR16, cls)) {
        Tx_Duty_Charge(l, now, AIR16);
        n++;
    }
    return n;
}

/* BULK зупиняється на бюджеті мінус резерв; резерв лишається маякові. */
static void test_bulk_stops_before_beacon_reserve(void)
{
    TxDutyLedger l;
    Tx_Duty_Init(&l);
    uint32_t t = 1000u;

    unsigned bulk = send_greedy(&l, t, TX_DUTY_BULK, 1000u);
    ASSERT_EQ(bulk, (TX_DUTY_BUDGET_MS - TX_DUTY_BEACON_RESERVE_MS) / AIR16);   /* 196 */
    ASSERT_EQ(Tx_Duty_Allows(&l, t, AIR16, TX_DUTY_BULK), 0);

    unsigned beacons = send_greedy(&l, t, TX_DUTY_BEACON, 1000u);
    ASSERT_EQ(bulk * AIR16 + beacons * AIR16 <= TX_DUTY_BUDGET_MS, 1);
    ASSERT_EQ(beacons, (TX_DUTY_BUDGET_MS - bulk * AIR16) / AIR16);             /* 22 */
    ASSERT_EQ(Tx_Duty_Allows(&l, t, AIR16, TX_DUTY_BEACON), 0);
}

/* Відмова нічого не списує — інакше стукіт у зачинені двері сам би їх тримав. */
static void test_denied_frame_charges_nothing(void)
{
    TxDutyLedger l;
    Tx_Duty_Init(&l);
    uint32_t t = 5000u;
    (void)send_greedy(&l, t, TX_DUTY_BEACON, 1000u);
    uint32_t before = Tx_Duty_Spent_Ms(&l, t);
    for (int i = 0; i < 50; i++) ASSERT_EQ(Tx_Duty_Allows(&l, t, AIR16, TX_DUTY_BULK), 0);
    ASSERT_EQ(Tx_Duty_Spent_Ms(&l, t), before);
}

/* Бюджет повертається лише тоді, коли кошик із витратою виїхав за кільце:
 * на 60-й хвилині він ще в історії (5-хв запас — ціна ковзного вікна),
 * на 65-й — уже ні. */
static void test_budget_returns_only_after_ring(void)
{
    TxDutyLedger l;
    Tx_Duty_Init(&l);
    uint32_t t0 = 777u;
    (void)send_greedy(&l, t0, TX_DUTY_BULK, 1000u);

    ASSERT_EQ(Tx_Duty_Allows(&l, t0 + 30u * MIN_MS, AIR16, TX_DUTY_BULK), 0);
    ASSERT_EQ(Tx_Duty_Allows(&l, t0 + 60u * MIN_MS, AIR16, TX_DUTY_BULK), 0);
    ASSERT_EQ(Tx_Duty_Allows(&l, t0 + 65u * MIN_MS, AIR16, TX_DUTY_BULK), 1);
    ASSERT_EQ(Tx_Duty_Spent_Ms(&l, t0 + 65u * MIN_MS), 0u);
}

/* HAL_GetTick розгортається раз на 49.7 доби — межа не сміє ані відкрити
 * бюджет передчасно, ані замкнути його назавжди. */
static void test_tick_wraparound(void)
{
    TxDutyLedger l;
    Tx_Duty_Init(&l);
    uint32_t t0 = 0xFFFFFFFFu - 1000u;   /* за секунду до wrap */
    (void)send_greedy(&l, t0, TX_DUTY_BULK, 1000u);

    ASSERT_EQ(Tx_Duty_Allows(&l, t0 + 30u * MIN_MS, AIR16, TX_DUTY_BULK), 0); /* після wrap */
    ASSERT_EQ(Tx_Duty_Allows(&l, t0 + 65u * MIN_MS, AIR16, TX_DUTY_BULK), 1);
}

/* Довга тиша (понад кільце за одним кроком) чистить усе. */
static void test_long_silence_clears_ring(void)
{
    TxDutyLedger l;
    Tx_Duty_Init(&l);
    (void)send_greedy(&l, 42u, TX_DUTY_BEACON, 1000u);
    ASSERT_EQ(Tx_Duty_Spent_Ms(&l, 42u + 10u * 60u * MIN_MS), 0u);
    ASSERT_EQ(send_greedy(&l, 42u + 10u * 60u * MIN_MS, TX_DUTY_BULK, 1000u),
              (TX_DUTY_BUDGET_MS - TX_DUTY_BEACON_RESERVE_MS) / AIR16);
}

/* 🔴 Серце файлу — стеля ковзного вікна на довільному трафіку. Журнал кадрів
 * веде ТЕСТ, а не лімітер, тож лімітер не атестує сам себе. Трафік: жадібний
 * BULK щосекунди + маяк щоп'ятнадцять хвилин + LCG-сплески «hello» (перемотка
 * маяка) — дванадцять годин. */
#define LOG_MAX 4096u
static uint32_t g_log_t[LOG_MAX];
static unsigned g_log_n;

static uint32_t air_in_last_hour(uint32_t now)
{
    uint32_t sum = 0u;
    for (unsigned i = 0; i < g_log_n; i++) {
        if (now - g_log_t[i] < TX_DUTY_WINDOW_MS) sum += AIR16;
    }
    return sum;
}

static void try_send(TxDutyLedger *l, uint32_t now, TxDutyClass cls, uint32_t *worst)
{
    if (!Tx_Duty_Allows(l, now, AIR16, cls)) return;
    Tx_Duty_Charge(l, now, AIR16);
    if (g_log_n < LOG_MAX) g_log_t[g_log_n++] = now;
    uint32_t h = air_in_last_hour(now);
    if (h > *worst) *worst = h;
}

static void test_sliding_hour_never_exceeds_budget(void)
{
    TxDutyLedger l;
    Tx_Duty_Init(&l);
    g_log_n = 0u;
    uint32_t worst = 0u;
    uint32_t lcg = 12345u;
    const uint32_t t0 = 3u;

    for (uint32_t s = 0; s < 12u * 3600u; s++) {
        uint32_t now = t0 + s * 1000u;
        try_send(&l, now, TX_DUTY_BULK, &worst);
        if (s % 900u == 0u) try_send(&l, now, TX_DUTY_BEACON, &worst);
        lcg = lcg * 1103515245u + 12345u;
        if ((lcg >> 16) % 97u == 0u) try_send(&l, now, TX_DUTY_BEACON, &worst);
    }
    ASSERT_TRUE(g_log_n < LOG_MAX);            /* журнал не обрізано — вимір повний */
    ASSERT_TRUE(worst <= TX_DUTY_BUDGET_MS);   /* стеля ковзного вікна */
    /* Невакуумність: маяки теж сидять у сумі, яку бачить BULK (резерв — це
     * «останні 3.6 с лише маякові», не окремий рахунок), тож за першу годину
     * ефіру пройшло не менше за стелю BULK, округлену до цілого кадру. */
    ASSERT_TRUE(air_in_last_hour(t0 + 3599u * 1000u) >=
                ((TX_DUTY_BUDGET_MS - TX_DUTY_BEACON_RESERVE_MS) / AIR16) * AIR16);
}

/* Ціна, яку платить OTA: серія 8 КБ (745 кадрів тіла + 4 печатки) при
 * безперервному попиті закінчується не раніше ніж за три години — чотири
 * годинні порції по 196 кадрів. Верхня межа — невакуумність: кільце з
 * 5-хв кошиків додає до кожної порції ≤ 5 хв, не більше. */
static void test_ota_series_is_paced_over_hours(void)
{
    TxDutyLedger l;
    Tx_Duty_Init(&l);
    const unsigned frames = 745u + 4u;
    unsigned sent = 0u;
    uint32_t done_s = 0u;
    for (uint32_t s = 0; s < 6u * 3600u && sent < frames; s++) {
        uint32_t now = 11u + s * 1000u;
        if (Tx_Duty_Allows(&l, now, AIR16, TX_DUTY_BULK)) {
            Tx_Duty_Charge(&l, now, AIR16);
            if (++sent == frames) done_s = s;
        }
    }
    ASSERT_EQ(sent, frames);
    ASSERT_TRUE(done_s >= 3u * 3600u);               /* ≥ 3 год: стеля тримає */
    ASSERT_TRUE(done_s <= 3u * 3600u + 25u * 60u);   /* ≤ 3 год 25 хв: не зайва суворість */
}

int main(void)
{
    printf("── test_tx_duty: FW.61 лімітер робочого циклу TX Королеви ──\n");

    printf("test_bulk_stops_before_beacon_reserve\n");  test_bulk_stops_before_beacon_reserve();
    printf("test_denied_frame_charges_nothing\n");      test_denied_frame_charges_nothing();
    printf("test_budget_returns_only_after_ring\n");    test_budget_returns_only_after_ring();
    printf("test_tick_wraparound\n");                   test_tick_wraparound();
    printf("test_long_silence_clears_ring\n");          test_long_silence_clears_ring();
    printf("test_sliding_hour_never_exceeds_budget\n"); test_sliding_hour_never_exceeds_budget();
    printf("test_ota_series_is_paced_over_hours\n");    test_ota_series_is_paced_over_hours();

    printf("──────────────────────────────────────────────────────────\n");
    printf("PASS: %d  FAIL: %d\n", g_tests_run - g_tests_failed, g_tests_failed);
    return g_tests_failed == 0 ? 0 : 1;
}
