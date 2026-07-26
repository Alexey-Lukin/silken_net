// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * test_logmel_cmsis.c — [FW.46] Host packing-parity for the CMSIS RFFT path.
 *
 * Compiles Compute_LogMel with LOGMEL_USE_CMSIS against host-built CMSIS-DSP
 * (scalar path, -DHOST=ON) and runs the shared check core
 * (firmware/sim/logmel_parity_core.h): golden vectors + tone localization +
 * silence floor — proving the arm_rfft_fast_f32 output UNPACKING in logmel.c
 * ([re(0), re(N/2), re(1), im(1), …] → power[]) is correct, on the host, with
 * NO board.
 *
 * Scope: this verifies the PACKING (a swapped re/im or a misplaced DC/Nyquist
 * bin would error by orders of magnitude). The same core also runs on the real
 * Cortex-M4 code path (soft-float, QEMU mps2-an386) via
 * firmware/scripts/qemu_logmel.sh; silicon float32 confirm stays a thin bench
 * formality. The tolerance absorbs float32(CMSIS) vs double(silken_ml oracle)
 * numerics on log-floored silent bands — measured worst Δ is orders below it.
 *
 * Built + run by firmware/CMakeLists.txt (SILKEN_HOST_PARITY=ON) via ctest.
 */
#include <stdio.h>

#include "logmel_parity_core.h"

int main(void)
{
    float worst = 0.0f;
    int failed;

    printf("\n[FW.46] CMSIS log-mel packing-parity (host, no board)\n");
    failed = Logmel_Parity_Run(&worst);
    printf("[FW.46] worst D=%.3e (tol %.0e) — %s\n\n",
           (double)worst, (double)LOGMEL_PARITY_TOL, failed ? "FAIL" : "PASS");
    return failed ? 1 : 0;
}
