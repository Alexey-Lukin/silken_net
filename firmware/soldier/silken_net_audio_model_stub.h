/**
 ******************************************************************************
 * @file    silken_net_audio_model_stub.h
 * @brief   IP-friendly STUB for the TinyML acoustic model contract.
 *
 *          This stub unblocks BLOCKER-1+2 (`docs/03_03 §BLOCKER-1/2`) by
 *          providing the symbols that `firmware/soldier/main.c` references
 *          from `silken_net_audio_model.h`. The real model header is produced
 *          by the ML partner (Бушин/Любченко, `docs/08_02 §1B`) and
 *          contains TFLite quantized weights + tensor arena allocation; that
 *          file replaces this stub at integration time.
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
#define ML_CLASS_FAUNA_ACTIVITY  4u   /* Mongabay pivot, post-TRL 7 */

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
 * `arm-none-eabi-size firmware.elf` after the production model is loaded —
 * this is the "first action after BLOCKER-1 unblock" from §BLOCKER-3.
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
 * @note    Stub provides declaration only. Without the real model header
 *          the symbol is unresolved — keep the Phase 1.5 call-site in main.c
 *          commented out until BLOCKER-1 is closed.
 */
uint8_t Run_Inference(const float* buffer, float* confidence);

#endif /* SILKEN_NET_AUDIO_MODEL_STUB_H */
