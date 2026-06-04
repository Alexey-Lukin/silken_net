/*
 * logmel.c — Compute_LogMel: акустичний DSP-фронтенд Солдата (FW.25).
 *
 * Перетворює один 512-семпловий кадр на 40 log-mel ознак (docs/03_03 §3.4):
 *
 *   DC-remove (− mean per-frame) → periodic Hann → RFFT 512→257
 *   → power re²+im² → HTK mel-bank (sparse) → ln(·+1e-6)
 *
 * RFFT має два тіла:
 *   • на STM32 (LOGMEL_USE_CMSIS) — апаратно-дружній arm_rfft_fast_f32;
 *   • на host (тести) — портативний naive DFT: той самий точний DFT, що й
 *     Python-оракул silken_ml, тож golden-вектори збігаються в межах float32
 *     (tol 1e-3). Naive O(N²) тут навмисний — він очевидно-коректний (нема
 *     butterfly-багів), а кілька кадрів у тесті рахуються миттєво.
 *
 * Таблиці periodic-Hann і mel-bank — auto-generated (silken_ml.codegen),
 * вшиті як const з logmel_hann_table.h / logmel_mel_bank.h.
 */
#include "logmel.h"
#include "logmel_hann_table.h"
#include "logmel_mel_bank.h"

#include <math.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

#if defined(LOGMEL_USE_CMSIS)
#include "arm_math.h"
#include <string.h>
static arm_rfft_fast_instance_f32 s_rfft;
static int s_rfft_ready = 0;
#endif

/* RFFT кадру → power[257] (re²+im², без 1/N). */
static void logmel_rfft_power(const float windowed[LOGMEL_N_FFT],
                              float power[LOGMEL_N_BINS])
{
#if defined(LOGMEL_USE_CMSIS)
    /* STM32: апаратний arm_rfft_fast_f32. Пакування виходу CMSIS —
     * [re(0), re(N/2), re(1), im(1), …]; розпаковуємо у power[0..256].
     * (Силіконова верифікація пакування — bench, FW.2-клас.) */
    float fft_out[LOGMEL_N_FFT];
    float scratch[LOGMEL_N_FFT];
    int k;
    if (!s_rfft_ready) { arm_rfft_fast_init_f32(&s_rfft, LOGMEL_N_FFT); s_rfft_ready = 1; }
    memcpy(scratch, windowed, sizeof(scratch));
    arm_rfft_fast_f32(&s_rfft, scratch, fft_out, 0);
    power[0]                = fft_out[0] * fft_out[0];   /* DC bin       */
    power[LOGMEL_N_BINS - 1] = fft_out[1] * fft_out[1];  /* Nyquist bin  */
    for (k = 1; k < LOGMEL_N_BINS - 1; k++) {
        float re = fft_out[2 * k];
        float im = fft_out[2 * k + 1];
        power[k] = re * re + im * im;
    }
#else
    /* Host: naive real DFT як reference. Акумуляція у double — навмисно: задача
     * host-тесту довести коректність ТАБЛИЦЬ + пайплайна проти double-оракула, а
     * не float32-numerics. Naive-DFT float32 (O(N) ріст похибки) гірше
     * кондиціонований за device-овий arm_rfft_fast_f32 (O(log N) butterfly), тож
     * його шум на тихих смугах (через log-floor) перебільшував би помилку заліза.
     * float32-парність самого arm_rfft верифікується на STM32-bench. */
    int k, n;
    for (k = 0; k < LOGMEL_N_BINS; k++) {
        double re = 0.0, im = 0.0;
        double wk = -2.0 * M_PI * (double)k / (double)LOGMEL_N_FFT;
        for (n = 0; n < LOGMEL_N_FFT; n++) {
            double ang = wk * (double)n;
            re += (double)windowed[n] * cos(ang);
            im += (double)windowed[n] * sin(ang);
        }
        power[k] = (float)(re * re + im * im);
    }
#endif
}

void Compute_LogMel(const float audio[LOGMEL_N_FFT], float out_mel[LOGMEL_N_MELS])
{
    float windowed[LOGMEL_N_FFT];
    float power[LOGMEL_N_BINS];
    float mean = 0.0f;
    int i, m, t;

    /* 1. DC-remove (per-frame mean) — audio у [0,1) несе велику DC (≈0.5). */
    for (i = 0; i < LOGMEL_N_FFT; i++) mean += audio[i];
    mean /= (float)LOGMEL_N_FFT;

    /* 2. periodic Hann (вшита таблиця). */
    for (i = 0; i < LOGMEL_N_FFT; i++)
        windowed[i] = (audio[i] - mean) * LOGMEL_HANN[i];

    /* 3. RFFT → power. */
    logmel_rfft_power(windowed, power);

    /* 4. HTK mel-bank (sparse triplet): out_mel[m] += w · power[k]. */
    for (m = 0; m < LOGMEL_N_MELS; m++) out_mel[m] = 0.0f;
    for (t = 0; t < LOGMEL_MEL_NNZ; t++) {
        const logmel_mel_triplet_t *tr = &LOGMEL_MEL_BANK[t];
        out_mel[tr->m] += tr->w * power[tr->k];
    }

    /* 5. ln(·+1e-6). */
    for (m = 0; m < LOGMEL_N_MELS; m++)
        out_mel[m] = logf(out_mel[m] + LOGMEL_LOG_FLOOR);
}
