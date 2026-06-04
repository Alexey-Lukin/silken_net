/*
 * test_logmel_cmsis.c — [FW.46] Host packing-parity for the CMSIS RFFT path.
 *
 * Compiles Compute_LogMel with LOGMEL_USE_CMSIS against host-built CMSIS-DSP
 * (scalar path, -DHOST=ON) and checks it reproduces the golden vectors + a tone
 * localization, proving the arm_rfft_fast_f32 output UNPACKING in logmel.c
 * ([re(0), re(N/2), re(1), im(1), …] → power[]) is correct — on the host, with
 * NO board.
 *
 * Scope: this verifies the PACKING (a swapped re/im or a misplaced DC/Nyquist
 * bin would error by orders of magnitude). True on-silicon float32 bit-parity
 * stays bench-gated (FW.2). The tolerance therefore absorbs float32(CMSIS) vs
 * double(silken_ml oracle) numerics on log-floored silent bands.
 *
 * Built + run by firmware/CMakeLists.txt (SILKEN_HOST_PARITY=ON) via ctest.
 */
#include <stdio.h>
#include <math.h>

#include "logmel.h"
#include "logmel_golden_vectors.h"

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

/* Packing-correctness band — not bit-parity (see header). Measured worst Δ
 * (host CMSIS-scalar float32 vs double oracle) ≈ 7.6e-6, so 1e-3 (≈130× margin,
 * same as test_logmel.c) is a sensitive gate that still absorbs numerics. */
#define TOL        1e-3f
#define FLOOR_LOG  logf(LOGMEL_LOG_FLOOR)

int main(void)
{
    int failed = 0;
    float worst = 0.0f;

    printf("\n[FW.46] CMSIS log-mel packing-parity (host, no board)\n");

    /* 1. Golden-vector parity — the packing gate. */
    for (int g = 0; g < LOGMEL_GOLDEN_COUNT; g++) {
        float out[LOGMEL_N_MELS];
        Compute_LogMel(LOGMEL_GOLDEN[g].input, out);
        for (int m = 0; m < LOGMEL_N_MELS; m++) {
            float d = fabsf(out[m] - LOGMEL_GOLDEN[g].expected[m]);
            if (d > worst) worst = d;
            if (d > TOL) {
                printf("  ❌ golden[%s] band %d: expected %.5f got %.5f (Δ=%.3e)\n",
                       LOGMEL_GOLDEN[g].name, m, LOGMEL_GOLDEN[g].expected[m], out[m], d);
                failed++;
            }
        }
    }

    /* 2. Tone localization — the strongest packing check: a 2 kHz tone (FFT bin
     *    64) must peak in the mel output; a swapped/misindexed unpack would not. */
    {
        float in[LOGMEL_N_FFT], out[LOGMEL_N_MELS];
        float f = 64.0f * LOGMEL_SR / LOGMEL_N_FFT;
        for (int i = 0; i < LOGMEL_N_FFT; i++)
            in[i] = 0.5f + 0.4f * sinf(2.0f * (float)M_PI * f * (float)i / (float)LOGMEL_SR);
        Compute_LogMel(in, out);
        float mx = out[0];
        for (int m = 1; m < LOGMEL_N_MELS; m++) if (out[m] > mx) mx = out[m];
        if (!(mx > FLOOR_LOG + 5.0f)) {
            printf("  ❌ 2 kHz tone did not localize — suspect CMSIS unpack\n");
            failed++;
        }
    }

    /* 3. Silence → log-floor — DC/Nyquist unpack sanity. */
    {
        float in[LOGMEL_N_FFT] = {0}, out[LOGMEL_N_MELS];
        Compute_LogMel(in, out);
        for (int m = 0; m < LOGMEL_N_MELS; m++)
            if (fabsf(out[m] - FLOOR_LOG) > 1e-3f) {
                printf("  ❌ silence band %d off floor: %.5f\n", m, out[m]);
                failed++;
            }
    }

    printf("[FW.46] worst Δ=%.3e (tol %.2f) — %s\n\n",
           (double)worst, (double)TOL, failed ? "❌ FAIL" : "✅ PASS");
    return failed ? 1 : 0;
}
