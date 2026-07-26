// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * test_tdma_schedule.c — [ARCH.26 L2] host-тести слот-розкладки TDMA.
 *
 * Пінить wire-контракт байтів 5..8 маяка ДО bench-фліпу гейтів
 * (ARCH26_TDMA_ENABLED обабіч): pack↔parse roundtrip, fail-closed
 * валідація сміття, математика наступного вікна (строго майбутнє —
 * вхід WUT-армінгу), членство in-window у секундній гранулярності,
 * детермінізм DID-слотів. All-zero wire = TDMA off — байт-у-байт
 * нинішній ефір, регресійна точка сумісності зі старими прошивками.
 *
 * Канон: 03_02 §5а.2 (wire) + 03_01 §1.9 (рандеву L2) + 00_07 ARCH.26.
 */
#include <stdio.h>
#include <stdint.h>
#include <string.h>

#include "../common/tdma_schedule.h"

static int tests_passed = 0;
static int tests_failed = 0;

#define ASSERT_TRUE(expr) do { \
    if (expr) { tests_passed++; } \
    else { tests_failed++; \
           printf("  FAIL %s:%d: %s\n", __FILE__, __LINE__, #expr); } \
} while (0)

#define ASSERT_EQ(a, b) ASSERT_TRUE((a) == (b))

/* ── Pack: рівно 4 байти, сусіди недоторкані ─────────────────────────── */
static void test_pack_writes_exactly_four_bytes(void)
{
    printf("test_pack_writes_exactly_four_bytes\n");
    uint8_t buf[16];
    memset(buf, 0xAA, sizeof buf);   /* канарки обабіч цільового вікна */

    Tdma_Pack_Beacon_Bytes(15u, 20u, 4u, 0u, &buf[5]);

    ASSERT_EQ(buf[4], 0xAA);         /* ts-байт не зачеплено */
    ASSERT_EQ(buf[5], 15u);
    ASSERT_EQ(buf[6], 20u);
    ASSERT_EQ(buf[7], 4u);
    ASSERT_EQ(buf[8], 0u);
    ASSERT_EQ(buf[9], 0xAA);         /* AUTH|TTL-байт не зачеплено */
}

/* ── Roundtrip: Queen-константи → wire → розгорнутий розклад ─────────── */
static void test_pack_parse_roundtrip(void)
{
    printf("test_pack_parse_roundtrip\n");
    uint8_t wire[4];
    Tdma_Pack_Beacon_Bytes(15u, 20u, 4u, 0u, wire);

    TdmaSchedule s;
    ASSERT_EQ(Tdma_Parse_Beacon_Bytes(wire, &s), 1u);
    ASSERT_TRUE(Tdma_Enabled(&s));
    ASSERT_EQ(s.period_s,   900u);   /* 15 хв */
    ASSERT_EQ(s.window_ms, 2000u);   /* 20 × 100 мс */
    ASSERT_EQ(s.slot_count,   4u);
    ASSERT_EQ(s.phase_s,      0u);
}

/* ── All-zero wire = TDMA off (нинішній ефір, сумісність) ────────────── */
static void test_all_zero_wire_means_disabled(void)
{
    printf("test_all_zero_wire_means_disabled\n");
    uint8_t wire[4] = {0, 0, 0, 0};
    TdmaSchedule s;
    ASSERT_EQ(Tdma_Parse_Beacon_Bytes(wire, &s), 0u);
    ASSERT_TRUE(!Tdma_Enabled(&s));
    ASSERT_EQ(Tdma_Next_Window_Start(&s, 123456u), 0u);
    ASSERT_EQ(Tdma_In_Window(&s, 123456u), 0u);
    ASSERT_EQ(Tdma_Slot_For_Did(&s, 0xDEADBEEFu), 0u);
    ASSERT_EQ(Tdma_Slot_Tx_Offset_Ms(&s, 3u), 0u);
}

/* ── Fail-closed: сміття/бітфліп не вмикає розклад ───────────────────── */
static void test_parse_fail_closed_on_garbage(void)
{
    printf("test_parse_fail_closed_on_garbage\n");
    TdmaSchedule s;

    /* нульове вікно при живому періоді */
    uint8_t no_window[4] = {15u, 0u, 4u, 0u};
    ASSERT_EQ(Tdma_Parse_Beacon_Bytes(no_window, &s), 0u);
    ASSERT_TRUE(!Tdma_Enabled(&s));

    /* фаза на межі періоду: period 1 хв = 60 с, phase 15×4 = 60 с ≥ 60 → off */
    uint8_t phase_at_edge[4] = {1u, 20u, 0u, 15u};
    ASSERT_EQ(Tdma_Parse_Beacon_Bytes(phase_at_edge, &s), 0u);
    ASSERT_TRUE(!Tdma_Enabled(&s));

    /* фаза строго в періоді: 14×4 = 56 с < 60 → валідно */
    uint8_t phase_inside[4] = {1u, 20u, 0u, 14u};
    ASSERT_EQ(Tdma_Parse_Beacon_Bytes(phase_inside, &s), 1u);
    ASSERT_EQ(s.phase_s, 56u);

    /* попередній валідний стан затирається невалідним wire (fail-closed) */
    ASSERT_EQ(Tdma_Parse_Beacon_Bytes(no_window, &s), 0u);
    ASSERT_TRUE(!Tdma_Enabled(&s));
}

/* ── Наступне вікно: сітка unix_ts % period == phase, строго майбутнє ── */
static void test_next_window_grid_math(void)
{
    printf("test_next_window_grid_math\n");
    TdmaSchedule s = { 900u, 2000u, 4u, 0u };

    ASSERT_EQ(Tdma_Next_Window_Start(&s, 1000u), 1800u);  /* всередині циклу */
    ASSERT_EQ(Tdma_Next_Window_Start(&s, 1799u), 1800u);  /* за секунду до */
    ASSERT_EQ(Tdma_Next_Window_Start(&s, 1800u), 2700u);  /* точно на старті → наступне */

    /* з фазою 300 с: старти = 1200, 2100, 3000, ... */
    TdmaSchedule p = { 900u, 2000u, 4u, 300u };
    ASSERT_EQ(Tdma_Next_Window_Start(&p, 1000u), 1200u);
    ASSERT_EQ(Tdma_Next_Window_Start(&p, 1200u), 2100u);
    ASSERT_EQ(Tdma_Next_Window_Start(&p, 1300u), 2100u);

    /* повернений старт завжди лежить на сітці */
    uint32_t nw = Tdma_Next_Window_Start(&p, 987654321u);
    ASSERT_EQ(nw % 900u, 300u);
    ASSERT_TRUE(nw > 987654321u);
}

/* ── In-window: [start, start + window_ms) у секундній гранулярності ── */
static void test_in_window_boundaries(void)
{
    printf("test_in_window_boundaries\n");
    TdmaSchedule s = { 900u, 2000u, 4u, 0u };

    ASSERT_EQ(Tdma_In_Window(&s, 1800u), 1u);   /* старт вікна */
    ASSERT_EQ(Tdma_In_Window(&s, 1801u), 1u);   /* 1000 мс < 2000 */
    ASSERT_EQ(Tdma_In_Window(&s, 1802u), 0u);   /* 2000 мс — край, уже поза */
    ASSERT_EQ(Tdma_In_Window(&s, 1799u), 0u);   /* перед вікном */

    /* з фазою: вікно на 1200 */
    TdmaSchedule p = { 900u, 2000u, 4u, 300u };
    ASSERT_EQ(Tdma_In_Window(&p, 1200u), 1u);
    ASSERT_EQ(Tdma_In_Window(&p, 1201u), 1u);
    ASSERT_EQ(Tdma_In_Window(&p, 1202u), 0u);
    ASSERT_EQ(Tdma_In_Window(&p, 1199u), 0u);
}

/* ── Слоти: детермінізм від DID + рівномірний offset ─────────────────── */
static void test_slot_determinism_and_offsets(void)
{
    printf("test_slot_determinism_and_offsets\n");
    TdmaSchedule s = { 900u, 2000u, 4u, 0u };

    /* той самий DID → той самий слот (повторюваність між пробудженнями) */
    ASSERT_EQ(Tdma_Slot_For_Did(&s, 0x12345678u), Tdma_Slot_For_Did(&s, 0x12345678u));
    ASSERT_EQ(Tdma_Slot_For_Did(&s, 0x12345678u), (uint8_t)(0x12345678u % 4u));

    /* offset-сітка: 2000 мс / 4 слоти = 500 мс крок */
    ASSERT_EQ(Tdma_Slot_Tx_Offset_Ms(&s, 0u),    0u);
    ASSERT_EQ(Tdma_Slot_Tx_Offset_Ms(&s, 1u),  500u);
    ASSERT_EQ(Tdma_Slot_Tx_Offset_Ms(&s, 2u), 1000u);
    ASSERT_EQ(Tdma_Slot_Tx_Offset_Ms(&s, 3u), 1500u);

    /* unslotted (slot_count=0): слот 0, offset 0 — шли на старті вікна */
    TdmaSchedule u = { 900u, 2000u, 0u, 0u };
    ASSERT_EQ(Tdma_Slot_For_Did(&u, 0xDEADBEEFu), 0u);
    ASSERT_EQ(Tdma_Slot_Tx_Offset_Ms(&u, 0u), 0u);
}

/* ── Wire-межі: максимальні байти не переповнюють uint16-поля ────────── */
static void test_wire_extremes_no_overflow(void)
{
    printf("test_wire_extremes_no_overflow\n");
    uint8_t wire[4] = {255u, 255u, 255u, 255u};
    TdmaSchedule s;
    /* phase 255×4 = 1020 c < period 255×60 = 15300 с → валідно */
    ASSERT_EQ(Tdma_Parse_Beacon_Bytes(wire, &s), 1u);
    ASSERT_EQ(s.period_s,  15300u);
    ASSERT_EQ(s.window_ms, 25500u);
    ASSERT_EQ(s.slot_count,  255u);
    ASSERT_EQ(s.phase_s,    1020u);

    /* математика вікон живе і на межах */
    uint32_t nw = Tdma_Next_Window_Start(&s, 4000000000u);
    ASSERT_TRUE(nw > 4000000000u);
    ASSERT_EQ(nw % 15300u, 1020u);
    ASSERT_EQ(Tdma_Slot_Tx_Offset_Ms(&s, 254u), (uint16_t)((25500u * 254u) / 255u));
}

int main(void)
{
    printf("═══ [ARCH.26 L2] TDMA schedule host tests ═══\n");

    test_pack_writes_exactly_four_bytes();
    test_pack_parse_roundtrip();
    test_all_zero_wire_means_disabled();
    test_parse_fail_closed_on_garbage();
    test_next_window_grid_math();
    test_in_window_boundaries();
    test_slot_determinism_and_offsets();
    test_wire_extremes_no_overflow();

    printf("═══ Results: %d passed, %d failed ═══\n", tests_passed, tests_failed);
    return tests_failed != 0;
}
