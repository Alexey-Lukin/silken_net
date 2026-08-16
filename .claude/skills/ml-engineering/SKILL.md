---
name: ml-engineering
description: "Use when working on the silken_net ML surface — the TinyML acoustic model + log-mel DSP front-end (firmware/common/logmel*, tools/ml/), model training / dataset / INT8 export, golden-vector parity, or the backend Rumale stress-index ML. Operational playbook for the tools/ml `silken_ml` package, the three-impl parity model, and the local-verify recipes; routes to the 03_03 canon, does not restate the contract. Examples: \"edit the log-mel contract\", \"regenerate the firmware mel tables\", \"add a TinyML training step\", \"why does Compute_LogMel diverge\", \"set up the ML env\"."
---

# ML Engineering (`silken_ml` + edge TinyML)

The *executable playbook* for the project's machine-learning surface. This skill is
the **HOW**; it does **not** restate the feature contract or track state — those live
elsewhere (below). The whole point is the parity invariant: **train-side features ==
on-device features, proven, not hoped.**

## 📖 Read first — SSOT, do NOT restate here

| Source | Owns |
|---|---|
| `docs/03_03_TinyML_Acoustic_Inference.md §3.4` | **Log-mel feature contract** (SR / n_fft / mel / HTK / DC-removal / periodic-Hann / tol). The values live here; everything else mirrors. |
| `docs/03_03_TinyML_Acoustic_Inference.md §3.2/§4/§10` | DSP-path decision (Path B log-mel), model architecture (Path B, 5-class), Mongabay fauna (biodiversity = 2-й D-MRV вимір, both/and — не заміна carbon). |
| `tools/ml/README.md` | Package layout, the three-impl parity diagram, the local-verify recipes, the deferred stack. |
| `docs/00_06_SSOT_Documentation_Standard.md §2` | Canonical-home registry — the contract's home + its C/python mirrors + drift guard. |
| `docs/00_06_SSOT_Documentation_Standard.md §5` | 🚦 Validation Gate — LLM proposes a *hypothesis*, it does NOT compute physics; no code until the spec is approved. (Moved from the dissolved method page 2026-08-10.) |
| `docs/03_01_Firmware_Lifecycle_and_DMA.md §12.4` | **Firmware ARM cross-compile build** (FW.46) — CMake, pinned submodules (`firmware/extern/`), mrbc bytecode, toolchain pin, footprint, mruby `double`/NO_BOXING/minimal-gembox invariants. |

**State** (what's built / next) lives in memory, not here: `[[project_e61_done_next_machine_doable]]`, plus `[[feedback_no_volatile_counts]]`, `[[feedback_comment_style]]`.

## Core invariant — three implementations, one definition, proven equal

```
             03_03 §3.4  (contract SSOT, hash-stamped)
   librosa  ≡  pure-stdlib  ≡  C Compute_LogMel
 (training)   (fast local)    (firmware/common/logmel.c)
      └ parity 1e-6 ┘   └─ golden vectors, tol 1e-3 ─┘
```

- `silken_ml.dsp.logmel_librosa` — canonical, what a future ML partner trains on (numpy + librosa).
- `silken_ml.dsp.logmel_stdlib` — dependency-free; the fast local oracle; **generates the golden vectors**.
- `firmware/common/logmel.c` — on-device; consumes the generated tables; matched to the goldens.

`silken_ml.codegen.emit_c` emits the committed `firmware/common/logmel_*.h` (Hann, mel-bank, golden) and stamps the **contract hash** into each — a silent edit on any side turns a gate red. **No ML partner yet → we own the contract end-to-end and verify it locally.**

## Layered verification — fast (no conda) vs full (conda)

| Want | Run | Needs |
|---|---|---|
| C front-end ≡ goldens (tol 1e-3) | `make -C firmware/test logmel` | gcc only |
| C model ≡ silken_ml int-ref (class-exact + softmax + §8 #6/#7 smoke) | `make -C firmware/test audio_model` | gcc only |
| committed tables == contract | `python3 tools/ml/scripts/check_firmware_tables.py` | stdlib `python3` |
| regenerate tables after a contract change | `python3 -m silken_ml.codegen.emit_c` (`PYTHONPATH=tools/ml/src`) | stdlib |
| **librosa ≡ stdlib** parity (1e-6) + full suite | `pytest tools/ml/tests` | conda `silken_ml` |
| canonical regen idempotence | `silken-ml-gen-logmel --check` | conda `silken_ml` |

Set up the heavy env once: `mamba env create -f tools/ml/environment.yml && mamba run -n silken_ml pip install -e tools/ml`.

**CI:** `ci.yml › firmware_test` is light (gcc + the stdlib table check + the bytecode stamp check — no conda); `ci.yml › firmware_arm_build` is the heavy ARM gate (toolchain + submodules: cross-compile + bytecode regen-diff + VM harness + FFT parity); `ml_smoke.yml` is heavy/path-filtered (micromamba-cached: pytest + the librosa parity gate + `emit_c --check`).

## ARM cross-compile + bytecode (FW.46)

Firmware build canon — `03_01 §12.4` (CMake, pinned submodules, toolchain
pin, footprint, mruby invariants). `git submodule update --init --recursive`
first. **No ARM toolchain in this env by default** — pin Arm GNU 13.2.Rel1
(ARM tarball or apt `gcc-arm-none-eabi`); CI installs it. Operational recipes:

| Want | Run | Needs |
|---|---|---|
| cross-compile owned code (logmel.c) + `arm-none-eabi-size` | `cmake -B firmware/build -S firmware --toolchain $PWD/firmware/cmake/arm-none-eabi.cmake -DCMSISCORE=$PWD/firmware/extern/CMSIS_6/CMSIS/Core && cmake --build firmware/build --target size` (toolchain path **must be absolute** — cmake resolves it vs the build dir) | arm-gcc, cmake |
| regenerate the bytecode mirror after editing `bio_contract.rb` | `tools/firmware/gen_bytecode.sh` then commit `firmware/common/lorenz_bytecode.h` | ruby+rake (builds host mrbc) |
| bytecode mirror == source (light / deep) | `python3 tools/firmware/check_bytecode.py` / `tools/firmware/gen_bytecode.sh --check` | stdlib / +mrbc |
| minimal VM runs the committed bytecode | `tools/firmware/run_bytecode_vm.sh` | host cc + ruby |
| CMSIS RFFT packing == goldens (host, no board) | `cmake -B firmware/build-host -S firmware -DSILKEN_HOST_PARITY=ON -DHOST=ON -DCMSISCORE=… && ctest --test-dir firmware/build-host` | host cc, cmake |
| CMSIS path on the real M4 ISA + stack high-water (QEMU mps2-an386, soft-float = WLE5 ABI; same check core `firmware/sim/logmel_parity_core.h`) | `firmware/scripts/qemu_logmel.sh` (local = cross-build + honest skip; CI `REQUIRE_QEMU=1`) | arm-gcc, cmake, qemu-system-arm |

**mruby gotchas** (canon `03_01 §12.4` + `firmware/extern/mruby/doc/mruby4.0.md`): float flag is
`MRB_USE_FLOAT32` (renamed from `MRB_USE_FLOAT`); never enable WORD/NAN boxing
on 32-bit (no inline float → heap-thrash); minimal gembox = core +
`mruby-compar-ext` only. The committed bytecode was a placeholder stub before
FW.46 — `gen_bytecode.sh` produces the real compiled `bio_contract.rb`. Editing
a log-mel param OR the bytecode logic touches the contract dance AND these gates.

## Changing the contract (the One-Home dance)

Editing a log-mel parameter touches **three homes** — keep them in lockstep:

1. **`03_03 §3.4`** (owner) — edit the value via the `ssot-maintenance` skill; run `docs:check_refs`.
2. **`tools/ml/.../dsp/contract.py`** + **`firmware/common/logmel_contract.h`** — mirror the value.
3. **Regenerate** `firmware/common/logmel_*.h` (`emit_c`), **re-pin** the hash in `tools/ml/tests/test_contract_hash.py`, **re-run** `make -C firmware/test logmel` + `pytest`.

The `contract_hash` + `emit_c --check` catch any side left behind. **Audit inbound cross-refs to 03_03** when you change the input shape / preprocessing — drift-linters catch owned *values*, not "the same fact in other words" (e.g. "512 raw input" or "MFCC" prose elsewhere); that's a manual sweep.

## The baseline acoustic model + INT8 export (FW.4 — landed)

`silken_ml.{data,models,train,export}` are **filled** (no longer scaffolds): a self-owned
ESC-50 per-frame baseline (40 log-mel → hidden → 5, INT8). Method + honesty home is
`tools/ml/docs/baseline_model_program.md`; TF lives in the `silken_ml` env (PTQ + parity only).

**Runtime = a fixed-topology INT8 forward pass in pure C** (host≡ARM, the `logmel.c` idiom), zero new
vendoring — **NOT TFLM**. 🔑 TFLM is an *interpreter that delegates to CMSIS-NN* on Cortex-M (two layers,
not alternatives — a common category-error in the docs); its ~16-20 KB Flash + 4 KB SRAM framework sits on
TOP of the arena → marginal on the post-FW.55 budget (38 KB mruby → a ~7-15 KB arena ceiling) → documented
as a fallback only IF OTA-graph-flexibility is needed AND a measured footprint fits. The per-frame contract
`Run_Inference(float[40], float*)` keeps `MODEL_INPUT_SIZE=40` exact so a partner model = a drop-in header swap.

**Export pipeline** (`silken_ml.export`): fold Normalization→fc1 → INT8 PTQ (`TFLiteConverter`,
real-log-mel representative set) → extract per-channel params → **QUANTIZATION-PARITY gate**
(numpy int-ref == TFLite interpreter; `raise` if `argmax_mismatch≠0 || max|Δlogit|>1`) → emit
`firmware/soldier/silken_net_audio_model.h` (pure-C gemmlowp forward pass) + the host golden.

| Want | How (`silken_ml` env) |
|---|---|
| full retrain → header (re-quantizes; may churn weights) | `from silken_ml.export import build_from_run; build_from_run('tools/ml/models/registry/<run>')` |
| **banner/golden-only re-emit, ZERO weight churn** | `extract_params(<run>/model_int8.tflite) + emit_header(p, prov)` / `emit_golden(p, X)` — the committed `.tflite` is the deterministic anchor; `git diff` the `.h` must show banner-only |
| C model ≡ int-ref + §8 #6/#7 decision smoke | `make -C firmware/test audio_model` (gcc) |

`emit_golden` auto-selects **per-predicted-class** coverage (round-robin so the n_golden cap never
drops a class → ≥1 cavitation/chainsaw frame for the `03_03 §8` #6/#7 smoke).

**Registry provenance** (`tools/ml/.gitignore`): commit the SMALL provenance (`reproducibility` /
`export_report` / `data_manifest` `.json` + `model_int8.tflite` + `norm_stats.npz`) so the header's
`run`/`data-manifest` hashes are auditable + the header re-emittable; heavy/regenerable artifacts
(`model.keras`, PTQ `*.npz`, TF SavedModel temp) stay ignored.

**Honesty (don't conflate the two halves):** per-class field-validity is canon in `03_03 §4.2` —
silence + cavitation are **synthetic placeholders**; baseline accuracy is a **pipeline-integrity**
metric, NOT field accuracy. ⚠️ cavitation is deeper than "not validated" — it's an **audible-proxy,
not the real signal**: true xylem-cavitation acoustic emission is ultrasonic 25–150 kHz (Tyree&Dixon
1983; `UNI.11`), **beyond this chain's 16 kHz / Nyquist-8**, so `gen_cavitation` synthesises 5–8 kHz
clicks *under the Nyquist ceiling*, not from physics — the class trains a low-freq structural proxy,
never true AE (real detection needs a dedicated high-rate channel / v3). A future partner CNN is a
drop-in header swap (the `_stub.h` `__has_include` fallback stays).

## Two ML domains — keep the boundary

- **Edge TinyML** (this package): acoustic 5-class CNN + log-mel front-end + INT8 export → C. Python + firmware C.
- **Backend stress-index ML** (`lib/tasks/ai_train.rake`, `InsightGeneratorService`): Ruby Rumale RandomForest over `AiInsight`/`TelemetryLog`. *Known MVP debt* (Marshal serialization, no eval/split/registry) — harden separately; don't fold it into the edge package.

## Gotchas (hard-won)

- **Float literals**: `%.9g` of a whole number drops the point → `0f` is an *invalid octal constant* in C. The codegen forces a `.`/`e` (`c_float`). Don't hand-edit generated headers.
- **Host DFT accumulates in double** *on purpose* — it's a reference for the table/pipeline test; naive float32 DFT (O(N) error) is worse-conditioned than the device `arm_rfft_fast_f32` and its log-floor noise on silent bands over-reads error. On-target float32 FFT parity is **STM32-bench-gated**, not host.
- **Periodic Hann, not `arm_hanning_f32`** (that one is symmetric, denom N−1) → use the precomputed table.
- **conda `soundfile`** is pulled transitively by `librosa` — don't pin it by name (the conda-forge name bites).
- **`acoustic_events` counts BOTH critical classes, and a backend money-comment says otherwise** [ARCH.102, measured 2026-08-16]: the firmware counter increments on class 2 (cavitation) AND class 3 (chainsaw), in the CRITICAL and WARNING zones alike — the three increment sites are mutually exclusive `if/else if` branches, so ≤1 per wake. `InsightGeneratorService`'s "This field is CAVITATION only … so this term NEVER slashes a forester for third-party logging" stands on that false premise: today only the term's ENV-inertness protects the forester, not the stated mechanism. And no "insect" class exists at all (the 5 are silence·wind·cavitation·chainsaw·fauna, and cavitation itself is the audible proxy above), so the count can honestly claim "detector hits since the last successful uplink" — never WHICH threat, and never insects. Downstream threshold verdicts + wire semantics → `00_07` ARCH.102 + `03_03 §5` + skill `telemetry-pipeline`.
- **`.c` comments**: Ukrainian + the file's poetic house style (`[[feedback_comment_style]]`).
- **No commit/push** unless asked; verify the diff scope before any commit (Ruby side).

## Keep this skill bounded

This file is the **method**. The contract values → `03_03 §3.4`; the package details →
`tools/ml/README.md`; state/backlog → memory. If you're tempted to paste a parameter or a
file-line here, it belongs in one of those homes — that discipline is what the skill enforces.
