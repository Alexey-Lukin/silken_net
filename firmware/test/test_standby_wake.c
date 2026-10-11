// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * test_standby_wake.c — [FW.54] рішення «пробудження зі Standby ⊥ холодний старт» і порядок входу в
 * Standby (standby_wake.h), host.
 *
 * Що ловить: OR замість AND у рішенні (холодний старт, прочитаний як пробудження, відновив би сміттєві
 * DR); маркер, що не пишеться на КОЖНОМУ вході (FW.66 (Б) · S5: доти маркером був DR19 стану Лоренца,
 * який пишуть лише за валідного стану), і маркер, якому довіряють частково битим; переставлені кроки
 * входу (маркер не першим · APC до конфігурації pull-ів · WUF, знятий не останнім перед входом);
 * пропущений або подвоєний крок. Банк RTC-фічі за 03_01 §2.2 п. 6: холодний старт · roundtrip · бітфліп.
 * Чого не ловить: що WL-HAL справді має ці функції (це судить compile-lane hal_check_ccm з
 * FW54_STANDBY_ENABLED=1 — лише CCM-збірку; ECB-збірку з цим гейтом не компілює жоден лейн) і що
 * кремній засинає на ~300 нА (стенд, 00_07 FW.54); проводку маркера в main.c судить awk-пін, не цей файл.
 *
 * Build: make -C firmware/test standby_wake
 */
#include <stdio.h>
#include <string.h>

#include "../common/standby_wake.h"

static int tests_passed = 0;
static int tests_failed = 0;

#define CHECK(cond, msg) do { \
    if (cond) { tests_passed++; } \
    else { tests_failed++; printf("  ❌ %s\n", msg); } \
} while (0)

static char journal[16];
static int journal_len = 0;
static uint32_t fake_marker_dr = 0u;   /* backup-регістр маркера; холодний старт = 0 */

static void rec(char c) { if (journal_len < (int)sizeof(journal) - 1) journal[journal_len++] = c; }
static void op_marker(void) { rec('M'); fake_marker_dr = SILKEN_STANDBY_WAKE_MAGIC; }
static void op_pulls(void)  { rec('P'); }
static void op_apc(void)    { rec('A'); }
static void op_sram(void)   { rec('S'); }
static void op_wuf(void)    { rec('W'); }
static void op_enter(void)  { rec('E'); }

static const SilkenStandbyOps ops = { op_marker, op_pulls, op_apc, op_sram, op_wuf, op_enter };

static void reset_journal(void)
{
    memset(journal, 0, sizeof(journal));
    journal_len = 0;
}

static void test_decision_truth_table(void)
{
    const uint32_t m = SILKEN_STANDBY_WAKE_MAGIC;
    CHECK(Silken_Wake_From_Standby(1, m) == 1, "C1SBF + цілий маркер = пробудження зі Standby");
    CHECK(Silken_Wake_From_Standby(1, 0) == 0, "C1SBF без маркера = холодний старт (не відновлювати сміття)");
    CHECK(Silken_Wake_From_Standby(0, m) == 0, "маркер без C1SBF = холодний старт (reset при живому домені)");
    CHECK(Silken_Wake_From_Standby(0, 0) == 0, "нічого = холодний старт");
    CHECK(Silken_Wake_From_Standby(0x80, m) == 1, "будь-яке ненульове значення C1SBF читається як 1");
    CHECK(Silken_Wake_From_Standby(1, 0xFFFFFFFFu) == 0, "стертий домен (усі одиниці) — не маркер");
}

/* 03_01 §2.2 п. 6 (а): холодний старт — домен порожній, пробудження немає, хоч би що казав C1SBF. */
static void test_marker_cold_boot(void)
{
    fake_marker_dr = 0u;
    CHECK(Silken_Wake_From_Standby(1, fake_marker_dr) == 0, "холодний старт: маркера немає → не пробудження");
}

/* (б) roundtrip: вхід у Standby сам пише маркер (крок 1 шва) — і пробудження читається пробудженням
 * щоразу, хоч би що стерло маркер між снами (main() гасить його після читання). Що крок 1 у main.c
 * справді пише магію в DR7 безумовно, читає її рішення й гасить — host не бачить: це awk-пін
 * `make -C firmware/test standby_wake` над текстом main.c. */
static void test_marker_written_on_every_entry(void)
{
    for (int i = 0; i < 3; i++) {
        fake_marker_dr = 0u;   /* хоч би що стерло його між снами — вхід пише знову */
        reset_journal();
        Silken_Standby_Enter(&ops);
        CHECK(Silken_Wake_From_Standby(1, fake_marker_dr) == 1, "маркер записано входом → пробудження");
    }
}

/* (в) бітфліп у маркері — холодний старт, а не довіра частково битому домену. */
static void test_marker_bit_flip_reads_cold(void)
{
    for (int bit = 0; bit < 32; bit++) {
        CHECK(Silken_Wake_From_Standby(1, SILKEN_STANDBY_WAKE_MAGIC ^ (1UL << bit)) == 0,
              "один перевернутий біт маркера → холодний старт");
    }
}

static void test_entry_order(void)
{
    reset_journal();
    Silken_Standby_Enter(&ops);
    CHECK(strcmp(journal, "MPASWE") == 0, "порядок: маркер → pull-и → APC → без SRAM2 → зняти WUF → Standby");
    CHECK(journal_len == 6, "кожен крок рівно один раз");
    CHECK(journal[0] == 'M', "маркер — перший крок: після стану, який викликач уже записав у DR");
    CHECK(journal[journal_len - 1] == 'E', "вхід у Standby — останній крок");
    CHECK(strchr(journal, 'P') < strchr(journal, 'A'), "pull-и сконфігуровано до APC");
    CHECK(strchr(journal, 'W') + 1 == strchr(journal, 'E'), "WUF знято безпосередньо перед входом");
}

int main(void)
{
    printf("[FW.54] standby_wake.h — рішення пробудження й порядок входу в Standby\n");
    test_decision_truth_table();
    test_marker_cold_boot();
    test_marker_written_on_every_entry();
    test_marker_bit_flip_reads_cold();
    test_entry_order();
    printf("  %d passed, %d failed\n", tests_passed, tests_failed);
    return tests_failed == 0 ? 0 : 1;
}
