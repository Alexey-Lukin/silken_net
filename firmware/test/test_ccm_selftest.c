/*
 * test_ccm_selftest.c — Host verification of the on-target CCM self-test.
 *
 * [FW.2 / ARCH.42 Variant B] Builds `firmware/common/ccm_selftest.h` against
 * the OpenSSL-backed mock HAL and asserts every KAT passes. This proves the
 * self-test LOGIC + the baked KAT vectors are correct, so when the same code
 * runs on the STM32WLE5JC bench (real CRYP) a PASS is trustworthy and a FAIL
 * unambiguously points at the silicon / HAL invocation, not the test.
 *
 * Build & run:  make -C firmware/test selftest
 */
#define HAL_MOCK_CCM_ENABLED

#include "hal_mock.h"
#include "../common/lora_ccm.h"
#include "../common/ccm_selftest.h"
#include <stdio.h>

static CRYP_HandleTypeDef hcryp;
static int g_any_fail = 0;

static void report(const char *name, int pass) {
    printf("  %-44s %s\n", name, pass ? "\xE2\x9C\x85" : "FAIL");
    if (!pass) g_any_fail = 1;
}

int main(void) {
    printf("════════════════════════════════════════════════════════════════════\n");
    printf("  [FW.2] CCM on-target self-test — host (OpenSSL mock) verification\n");
    printf("════════════════════════════════════════════════════════════════════\n");

    int failed = Ccm_Run_Self_Test(&hcryp, report);

    printf("════════════════════════════════════════════════════════════════════\n");
    printf("KAT vectors failed: %d\n", failed);
    /* On host the mock IS OpenSSL, so this MUST be 0. A non-zero here means a
     * baked vector or the self-test logic is wrong — NOT a silicon issue. */
    return (failed == 0 && !g_any_fail) ? 0 : 1;
}
