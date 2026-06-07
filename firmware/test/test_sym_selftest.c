/*
 * test_sym_selftest.c — Host verification of the on-target ECB/CBC self-test.
 *
 * [ARCH.42] Builds `firmware/common/sym_selftest.h` against the
 * OpenSSL-backed mock HAL (HAL_MOCK_SYM_ENABLED) and asserts the NIST
 * SP 800-38A KATs pass. This proves the self-test LOGIC + baked vectors, so
 * a bench FAIL on STM32WLE5JC unambiguously points at the CRYP config
 * (DataType/endianness — DATATYPE_32B word-swap class) or silicon, not the
 * test. A bench PASS = «кремній == OpenSSL == backend» для ECB LoRa та
 * CBC CoAP транзитних шляхів ARCH.42.
 *
 * Build & run:  make -C firmware/test sym_selftest
 */
#define HAL_MOCK_SYM_ENABLED

#include "hal_mock.h"
#include "../common/sym_selftest.h"
#include <stdio.h>

static CRYP_HandleTypeDef hcryp;
static int g_any_fail = 0;

static void report(const char *name, int pass) {
    printf("  %-44s %s\n", name, pass ? "\xE2\x9C\x85" : "FAIL");
    if (!pass) g_any_fail = 1;
}

int main(void) {
    printf("════════════════════════════════════════════════════════════════════\n");
    printf("  [ARCH.42] ECB/CBC on-target self-test — host (OpenSSL mock)\n");
    printf("════════════════════════════════════════════════════════════════════\n");

    int failed = Sym_Run_Self_Test(&hcryp, report);

    printf("════════════════════════════════════════════════════════════════════\n");
    printf("SYM KAT vectors failed: %d\n", failed);
    /* On host the mock IS OpenSSL → MUST be 0; non-zero = vector/logic bug. */
    return (failed == 0 && !g_any_fail) ? 0 : 1;
}
