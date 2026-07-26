// SPDX-License-Identifier: AGPL-3.0-or-later
/*
 * logmel.h — Compute_LogMel: акустичний DSP-фронтенд Солдата (FW.25).
 *
 * Один 512-семпловий кадр (32 мс @ 16 кГц) → 40 log-mel ознак для TinyML
 * (Path B, docs/03_03 §3.4). Контракт значень — logmel_contract.h.
 */
#ifndef LOGMEL_H
#define LOGMEL_H

#include "logmel_contract.h"

/* Перетворює один кадр сирого аудіо на 40 log-mel ознак.
 *   audio:   512 нормалізованих [0,1) семплів (як audio_buffer[] у main.c) —
 *            DC прибирається всередині (per-frame mean).
 *   out_mel: 40 float; далі → Run_Inference(out_mel, &confidence).
 * Пайплайн: DC-remove → periodic Hann → RFFT 512→257 → power → HTK mel-bank → ln(+1e-6). */
void Compute_LogMel(const float audio[LOGMEL_N_FFT], float out_mel[LOGMEL_N_MELS]);

#endif /* LOGMEL_H */
