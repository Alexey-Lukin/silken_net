// SPDX-License-Identifier: AGPL-3.0-or-later
/**
 ******************************************************************************
 * @file    silken_net_audio_model_stub.h
 * @brief   IP-friendly STUB for the TinyML acoustic model contract.
 *
 *          FALLBACK when `silken_net_audio_model.h` is absent: provides the
 *          symbols that `firmware/soldier/main.c` references so the build still
 *          compiles. The PRIMARY header now EXISTS — a self-owned INT8 baseline
 *          (ESC-50, FW.4, `silken_ml.export`, gemmlowp pure-C forward pass); a
 *          future partner/field model (Любченко + Cherkasy soundscape,
 *          `docs/07_03 §1.1` (Любченко, ЧНУ ФОТІУС)) replaces it. FW.4 closed the model gap 2026-06-12 (model
 *          landed, call-site uncommented).
 *
 *          With this stub present the ARM toolchain can compile main.c and
 *          run `arm-none-eabi-size firmware.elf` / `make size-check` to
 *          measure the RAM budget without disclosing model IP.
 *
 *          DSP-path decision (`docs/03_03 §3.2`, FW.25, 2026-05-22):
 *          **Path B (log-mel spectrogram + 2D CNN)** is the official baseline.
 *          The constants below reflect that path; ML partner overrides them
 *          in the real header if Path A or C is selected as fallback.
 *
 * @note    `Run_Inference()` is declared here but **not defined**. The real
 *          model.h ships an inline definition that consumes the TFLite Micro
 *          interpreter. Until that arrives, callers must guard the call site
 *          (currently commented at the Phase 1.5 call-site in main.c).
 ******************************************************************************
 */
#ifndef SILKEN_NET_AUDIO_MODEL_STUB_H
#define SILKEN_NET_AUDIO_MODEL_STUB_H

#include <stdint.h>

/* === Model contract — single source of truth for class IDs ============== */

#define ML_CLASS_SILENCE         0u
#define ML_CLASS_WIND            1u
#define ML_CLASS_CAVITATION      2u
#define ML_CLASS_CHAINSAW        3u
#define ML_CLASS_FAUNA           4u   /* Mongabay pivot, post-TRL 7 */

#define NUM_CLASSES              5u

/* === Input tensor geometry =============================================== */
/* Path B (log-mel) baseline: 40 mel bands × N frames inferred per inference
 * window. For 32 ms @ 16 kHz the model receives one 40×1 column per call;
 * the 5-second fauna window aggregates 156 such columns via Welford
 * (`docs/03_03 §10.2`, ARCH.40).
 *
 * Path A fallback (raw 1D CNN) would set this to 512. ML partner declares the
 * real value in the production header.
 */
#define MODEL_INPUT_SIZE         40u

/* === Tensor Arena estimate (Path B baseline) ============================ */
/* 16 KB is the conservative estimate from `docs/03_03 §3.2 Decision Matrix`
 * (~15–30 KB range for Path B). Real value must be measured via
 * `arm-none-eabi-size firmware.elf`. The PRIMARY baseline (FW.4) measured
 * ~76 B (forward-pass, stack); this stub keeps the 16 KB worst-case for a
 * fallback TFLM-class model.
 */
#define TENSOR_ARENA_SIZE        (16u * 1024u)

/* === Inference entry point (declaration only) ========================== */
/**
 * @brief   Run a single TinyML inference on the audio buffer.
 *
 * @param   buffer       Normalized audio features (Path B: 40 mel bands).
 *                        Caller is responsible for log-mel pre-processing via
 *                        `arm_rfft_fast_f32` + custom Mel-bank + `arm_vlog_f32`
 *                        (see `docs/03_03 §3.2`).
 * @param   confidence   Output — softmax probability of the returned class
 *                        in [0.0, 1.0]. Passed to the FW.18 dual-threshold
 *                        zone decision (SILENCE / WARNING / CRITICAL).
 *
 * @return  Class ID in [0, NUM_CLASSES). See ML_CLASS_* macros above.
 *
 * @note    Stub provides declaration only (fallback). The PRIMARY header ships
 *          an inline `Run_Inference` definition (FW.4); with this stub alone the
 *          symbol is unresolved at link — the fallback compiles but cannot run
 *          inference until the real header is present.
 */
uint8_t Run_Inference(const float* buffer, float* confidence);

#endif /* SILKEN_NET_AUDIO_MODEL_STUB_H */
