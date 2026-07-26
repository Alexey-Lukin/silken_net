// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * logmel_contract.h — Log-mel feature contract (MIRROR of docs/03_03 §3.4).
 *
 * [FW.25] C-side single source of truth for the 512-sample → 40-band log-mel
 * front-end, shared by firmware/common/logmel.c and the host tests. The VALUES
 * are owned by docs/03_03 §3.4; this header AND
 * tools/ml/src/silken_ml/dsp/contract.py mirror them — keep all three in sync.
 *
 *   contract hash: 0cd21eb3c2d89ac6   (значення тут — дзеркало SSOT, правити там)
 *
 * Генеровані таблиці (periodic Hann, HTK mel-bank sparse, golden-vectors) —
 * `python -m silken_ml.codegen.emit_c` → logmel_{hann_table,mel_bank,
 * golden_vectors}.h (теж у цій теці, auto-generated).
 */
#ifndef LOGMEL_CONTRACT_H
#define LOGMEL_CONTRACT_H

#define LOGMEL_SR          16000    /* частота дискретизації (Гц) — TIM2 метроном */
#define LOGMEL_N_FFT       512      /* кадр (= 32 мс @ 16 кГц) = один DMA-блок    */
#define LOGMEL_HOP         512      /* без overlap → 156 кадрів / 5 с fauna-вікно */
#define LOGMEL_N_BINS      257      /* N_FFT/2 + 1 (RFFT bins, з DC + Nyquist)     */
#define LOGMEL_N_MELS      40       /* вхід моделі на кадр (MODEL_INPUT_SIZE)      */
#define LOGMEL_FMIN        50.0f    /* нижня межа mel (Гц)                         */
#define LOGMEL_FMAX        8000.0f  /* верхня межа mel (Гц) = Nyquist @ 16 кГц     */
#define LOGMEL_LOG_FLOOR   1e-6f    /* ln(mel + floor) — натуральний log, проти log(0) */

#endif /* LOGMEL_CONTRACT_H */
