# `tools/ml/` — SilkenNet ML Engineering Toolkit (`silken_ml`)

The "set up once" home for the project's machine-learning surface — the ML peer
to `tools/in_silico/` (chemistry), `contracts/` (Solidity), `firmware/` (edge),
and Rails (backend). First module shipped: the **TinyML log-mel DSP front-end**
(FW.25); the training / dataset / INT8-export modules are scaffolded for when a
corpus and model land.

> **Contract SSOT:** [`docs/03_03 §3.4`](../../docs/03_03_TinyML_Acoustic_Inference.md).
> The values are owned there; `silken_ml.dsp.contract` and
> `firmware/common/logmel_contract.h` are labelled mirrors. **No ML partner yet
> → we own the contract end-to-end and verify it locally.**

## The core idea — three implementations, one definition, proven equal

```
        docs/03_03 §3.4  (SSOT contract)
                 │  mirrored (hash-checked) into:
     ┌───────────┼────────────────────────┐
 logmel_librosa   logmel_stdlib      logmel_contract.h + logmel.c
 (canonical,      (pure-stdlib,      (firmware C: host radix-2 /
  training)        no numpy)          ARM arm_rfft_fast_f32)
     └─ parity ────┘   └──── golden vectors ────┘
        tol 1e-6              tol 1e-3
```

- **`logmel_librosa`** — canonical, what a future ML partner trains on (heavy: numpy + librosa).
- **`logmel_stdlib`** — dependency-free; the *fast local* path; generates the golden vectors.
- **`firmware/common/logmel.c`** — on-device; consumes the generated tables; matched to the goldens.

A parity test asserts librosa ≡ stdlib (tol 1e-6), so the dependency-free path is
provably the same feature math. The codegen stamps a **contract hash** into every
generated header; a silent edit on any side turns a gate red.

## Layout

| Path | What |
|------|------|
| `src/silken_ml/dsp/contract.py` | Numeric contract (mirror of §3.4) + `contract_hash()` |
| `src/silken_ml/dsp/logmel_stdlib.py` | Pure-stdlib oracle (fast local + golden-gen) |
| `src/silken_ml/dsp/logmel_librosa.py` | Canonical librosa oracle (training-side) |
| `src/silken_ml/codegen/emit_c.py` | Emits `firmware/common/logmel_*.h` (`--check` drift gate) |
| `src/silken_ml/{data,models,train,export}/` | **Scaffold** — see each module's docstring |
| `scripts/check_firmware_tables.py` | Stdlib-only firmware-header drift check (light CI) |
| `tests/` | pytest: parity, properties, contract-hash, codegen |

## Verify locally

**Fast path — no conda (just `python3` + `gcc`):**

```bash
# 1. firmware tables match the contract (stdlib only)
python3 tools/ml/scripts/check_firmware_tables.py

# 2. regenerate the firmware tables after a contract change
python3 -m silken_ml.codegen.emit_c           # PYTHONPATH=tools/ml/src

# 3. the C front-end matches the golden vectors (tol 1e-3)
make -C firmware/test logmel
```

**Full path — conda `silken_ml` (adds the librosa parity gate):**

```bash
micromamba env create -f tools/ml/environment.yml   # or: mamba env create -f …
micromamba activate silken_ml
pip install -e tools/ml
pytest tools/ml/tests          # incl. librosa ≡ stdlib parity (tol 1e-6)
silken-ml-gen-logmel --check   # canonical regen idempotence
```

## CI

- **`ci.yml › firmware_test`** (light): `make -C firmware/test` (runs the log-mel
  host test) + `check_firmware_tables.py` (stdlib, no conda).
- **`ml_smoke.yml`** (heavy, path-filtered `tools/ml/**`, micromamba-cached):
  `pytest` + the librosa≡stdlib parity gate + `emit_c --check`.
- **`ci.yml › python_lint`** (light): `ruff check .` — style/bug lint for all
  `tools/**` Python (config: root `ruff.toml`; `pip install ruff`, no conda).

## Deferred stack (not installed yet, by design)

TensorFlow / tflite-runtime are **deferred** until the training + INT8-export
module lands — there is no dataset or model today, and the DSP front-end +
foundation are fully useful (and verifiable) without them. When training starts:
add TF to `environment.yml`, implement `models/` + `train/` + `export/` per their
scaffold docstrings (config-driven, seeded, reproducibility manifest, model
registry, eval/confusion/calibration), and the INT8 model replaces the stub via
`__has_include` in `firmware/soldier/main.c`.
