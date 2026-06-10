/*
 * logmel_parity_core.h — [FW.4] спільне ядро перевірки CMSIS-шляху Compute_LogMel.
 *
 * One-Home: host-ctest (firmware/test/test_logmel_cmsis.c — скалярний CMSIS-DSP,
 * -DHOST=ON) і QEMU-M4 нога (firmware/sim/qemu_m4/logmel_main.c — справжній
 * Cortex-M4 код-шлях, soft-float __aeabi_*, як на STM32WLE5JC) компілюють ЦІ
 * САМІ перевірки:
 *   1) golden-вектори (tol 1e-3) — пакування arm_rfft_fast_f32 + float32 проти
 *      double-оракула silken_ml;
 *   2) локалізація 2 кГц тону — найсильніший тест пакування (переплутаний
 *      re/im чи зміщений DC/Nyquist промахнувся б на порядки);
 *   3) тиша → log-floor — sanity DC/Nyquist.
 *
 * Щасливий шлях НЕ друкує (друк — лише на фейлі): QEMU-нога міряє стек навколо
 * чистих викликів, stdio всередині спотворив би high-water.
 *
 * Канон: 03_03 §3.4 (контракт) + 03_01 §12.7 (QEMU-метод); толеранс — смуга
 * packing-коректності, не біт-парність (виміряний worst Δ host-CMSIS ↔ оракул
 * на порядки нижче, запас зберігає чутливість гейта).
 */
#ifndef SILKEN_LOGMEL_PARITY_CORE_H
#define SILKEN_LOGMEL_PARITY_CORE_H

#include <stdio.h>
#include <math.h>

#include "logmel.h"
#include "logmel_golden_vectors.h"

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

#define LOGMEL_PARITY_TOL  1e-3f

/* Повертає кількість фейлів (0 = pass); *worst_out — найгірший Δ golden-парності. */
static int Logmel_Parity_Run(float *worst_out)
{
    const float floor_log = logf(LOGMEL_LOG_FLOOR);
    int failed = 0;
    float worst = 0.0f;

    /* 1. Golden-vector parity — гейт пакування. */
    for (int g = 0; g < LOGMEL_GOLDEN_COUNT; g++) {
        float out[LOGMEL_N_MELS];
        Compute_LogMel(LOGMEL_GOLDEN[g].input, out);
        for (int m = 0; m < LOGMEL_N_MELS; m++) {
            float d = fabsf(out[m] - LOGMEL_GOLDEN[g].expected[m]);
            if (d > worst) worst = d;
            if (d > LOGMEL_PARITY_TOL) {
                printf("  FAIL golden[%s] band %d: expected %.5f got %.5f (D=%.3e)\n",
                       LOGMEL_GOLDEN[g].name, m,
                       (double)LOGMEL_GOLDEN[g].expected[m], (double)out[m], (double)d);
                failed++;
            }
        }
    }

    /* 2. Локалізація тону: 2 кГц (FFT bin 64) мусить дати пік у mel-виході. */
    {
        float in[LOGMEL_N_FFT], out[LOGMEL_N_MELS];
        float f = 64.0f * LOGMEL_SR / LOGMEL_N_FFT;
        for (int i = 0; i < LOGMEL_N_FFT; i++)
            in[i] = 0.5f + 0.4f * sinf(2.0f * (float)M_PI * f * (float)i / (float)LOGMEL_SR);
        Compute_LogMel(in, out);
        {
            float mx = out[0];
            for (int m = 1; m < LOGMEL_N_MELS; m++) if (out[m] > mx) mx = out[m];
            if (!(mx > floor_log + 5.0f)) {
                printf("  FAIL 2 kHz tone did not localize — suspect CMSIS unpack\n");
                failed++;
            }
        }
    }

    /* 3. Тиша → log-floor. */
    {
        float in[LOGMEL_N_FFT] = {0}, out[LOGMEL_N_MELS];
        Compute_LogMel(in, out);
        for (int m = 0; m < LOGMEL_N_MELS; m++)
            if (fabsf(out[m] - floor_log) > LOGMEL_PARITY_TOL) {
                printf("  FAIL silence band %d off floor: %.5f\n", m, (double)out[m]);
                failed++;
            }
    }

    if (worst_out) *worst_out = worst;
    return failed;
}

#endif /* SILKEN_LOGMEL_PARITY_CORE_H */
