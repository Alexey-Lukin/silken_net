// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * test_standby_wake.c — [FW.54] рішення «пробудження зі Standby ⊥ холодний старт» і порядок входу в
 * Standby (standby_wake.h), host.
 *
 * Що ловить: OR замість AND у рішенні (холодний старт, прочитаний як пробудження, відновив би сміттєві
 * DR); переставлені кроки входу (APC до конфігурації pull-ів · WUF, знятий не останнім перед входом);
 * пропущений або подвоєний крок.
 * Чого не ловить: що WL-HAL справді має ці функції (це судить compile-lane hal_check_ccm з
 * FW54_STANDBY_ENABLED=1) і що кремній засинає на ~300 нА (стенд, 00_07 FW.54).
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

static void rec(char c) { if (journal_len < (int)sizeof(journal) - 1) journal[journal_len++] = c; }
static void op_pulls(void)  { rec('P'); }
static void op_apc(void)    { rec('A'); }
static void op_sram(void)   { rec('S'); }
static void op_wuf(void)    { rec('W'); }
static void op_enter(void)  { rec('E'); }

static void test_decision_truth_table(void)
{
    CHECK(Silken_Wake_From_Standby(1, 1) == 1, "C1SBF + цілий маркер = пробудження зі Standby");
    CHECK(Silken_Wake_From_Standby(1, 0) == 0, "C1SBF без маркера = холодний старт (не відновлювати сміття)");
    CHECK(Silken_Wake_From_Standby(0, 1) == 0, "маркер без C1SBF = холодний старт (reset при живому домені)");
    CHECK(Silken_Wake_From_Standby(0, 0) == 0, "нічого = холодний старт");
    CHECK(Silken_Wake_From_Standby(0x80, 0x40) == 1, "будь-яке ненульове значення читається як 1");
}

static void test_entry_order(void)
{
    const SilkenStandbyOps ops = { op_pulls, op_apc, op_sram, op_wuf, op_enter };
    memset(journal, 0, sizeof(journal));
    journal_len = 0;
    Silken_Standby_Enter(&ops);
    CHECK(strcmp(journal, "PASWE") == 0, "порядок: pull-и → APC → без SRAM2 → зняти WUF → Standby");
    CHECK(journal_len == 5, "кожен крок рівно один раз");
    CHECK(journal[journal_len - 1] == 'E', "вхід у Standby — останній крок");
    CHECK(strchr(journal, 'P') < strchr(journal, 'A'), "pull-и сконфігуровано до APC");
    CHECK(strchr(journal, 'W') + 1 == strchr(journal, 'E'), "WUF знято безпосередньо перед входом");
}

int main(void)
{
    printf("[FW.54] standby_wake.h — рішення пробудження й порядок входу в Standby\n");
    test_decision_truth_table();
    test_entry_order();
    printf("  %d passed, %d failed\n", tests_passed, tests_failed);
    return tests_failed == 0 ? 0 : 1;
}
