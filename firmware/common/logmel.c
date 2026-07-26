// SPDX-License-Identifier: AGPL-3.0-or-later
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
static arm_rfft_fast_instance_f32 s_rfft;
static int s_rfft_ready = 0;
#endif

/* RFFT кадру → power у низ work[0..LOGMEL_N_BINS) (re²+im², без 1/N).
 *
 * [FW.4 reuse-buffers] Стек — два буфери замість чотирьох: frame руйнується
 * (він уже нікому не потрібен після FFT), спектр пакується у work і квадрати
 * лягають in-place у його низ. Запис у work[k] завжди передує читанню
 * work[2k]/work[2k+1] лише з МАЙБУТНІХ ітерацій (2k > k при k ≥ 1), тож
 * жодне значення не затирається до використання; re(Nyquist) з work[1]
 * виймаємо до циклу. Числово — ті самі float-операції, що й до рефакторингу. */
// cppcheck-suppress constParameter // host-гілка лише читає frame, CMSIS-гілка РУЙНУЄ (pSrc RFFT)
static void logmel_rfft_power(float frame[LOGMEL_N_FFT],
                              float work[LOGMEL_N_FFT])
{
#if defined(LOGMEL_USE_CMSIS)
    /* STM32: arm_rfft_fast_f32 (pSrc руйнується — віддаємо frame без копії).
     * Пакування виходу CMSIS — [re(0), re(N/2), re(1), im(1), …]. Парність
     * пакування доведена host-ctest + QEMU-M4 ногою (qemu_logmel.sh);
     * silicon-confirm — формальність bench. */
    float nyq_re;
    int k;
    if (!s_rfft_ready) { arm_rfft_fast_init_f32(&s_rfft, LOGMEL_N_FFT); s_rfft_ready = 1; }
    arm_rfft_fast_f32(&s_rfft, frame, work, 0);
    nyq_re  = work[1];
    work[0] = work[0] * work[0];                         /* DC bin */
    for (k = 1; k < LOGMEL_N_BINS - 1; k++) {
        float re = work[2 * k];
        float im = work[2 * k + 1];
        work[k] = re * re + im * im;
    }
    work[LOGMEL_N_BINS - 1] = nyq_re * nyq_re;           /* Nyquist bin */
#else
    /* Host: naive real DFT як reference (frame лише читається, power лягає у
     * низ work). Акумуляція у double — навмисно: задача host-тесту довести
     * коректність ТАБЛИЦЬ + пайплайна проти double-оракула, а не
     * float32-numerics. Naive-DFT float32 (O(N) ріст похибки) гірше
     * кондиціонований за device-овий arm_rfft_fast_f32 (O(log N) butterfly),
     * тож його шум на тихих смугах (через log-floor) перебільшував би помилку
     * заліза. float32-парність arm_rfft — host-ctest + QEMU-M4 нога. */
    int k, n;
    for (k = 0; k < LOGMEL_N_BINS; k++) {
        double re = 0.0, im = 0.0;
        double wk = -2.0 * M_PI * (double)k / (double)LOGMEL_N_FFT;
        for (n = 0; n < LOGMEL_N_FFT; n++) {
            double ang = wk * (double)n;
            re += (double)frame[n] * cos(ang);
            im += (double)frame[n] * sin(ang);
        }
        work[k] = (float)(re * re + im * im);
    }
#endif
}

void Compute_LogMel(const float audio[LOGMEL_N_FFT], float out_mel[LOGMEL_N_MELS])
{
    /* [FW.4 reuse-buffers] Лише два кадрові буфери на весь пайплайн:
     * windowed руйнується RFFT'ом, power живе у низу work. */
    float windowed[LOGMEL_N_FFT];
    float work[LOGMEL_N_FFT];
    float mean = 0.0f;
    int i, m, t;

    /* 1. DC-remove (per-frame mean) — audio у [0,1) несе велику DC (≈0.5). */
    for (i = 0; i < LOGMEL_N_FFT; i++) mean += audio[i];
    mean /= (float)LOGMEL_N_FFT;

    /* 2. periodic Hann (вшита таблиця). */
    for (i = 0; i < LOGMEL_N_FFT; i++)
        windowed[i] = (audio[i] - mean) * LOGMEL_HANN[i];

    /* 3. RFFT → power (у низ work; windowed після цього мертвий). */
    logmel_rfft_power(windowed, work);

    /* 4. HTK mel-bank (sparse triplet): out_mel[m] += w · power[k]. */
    for (m = 0; m < LOGMEL_N_MELS; m++) out_mel[m] = 0.0f;
    for (t = 0; t < LOGMEL_MEL_NNZ; t++) {
        const logmel_mel_triplet_t *tr = &LOGMEL_MEL_BANK[t];
        out_mel[tr->m] += tr->w * work[tr->k];
    }

    /* 5. ln(·+1e-6). */
    for (m = 0; m < LOGMEL_N_MELS; m++)
        out_mel[m] = logf(out_mel[m] + LOGMEL_LOG_FLOOR);
}
