# SPDX-License-Identifier: AGPL-3.0-or-later
"""INT8 TFLite → ``silken_net_audio_model.h`` export — fold, quantize, emit, parity.

Pipeline (when a trained model exists, ``silken_ml.train``):

    keras model (Input→Norm→Dense→ReLU→Dense)
      → FOLD Normalization into fc1 → plain FC→ReLU→FC
      → ``TFLiteConverter`` INT8 post-training quantization (representative = real log-mel)
      → extract per-channel int8 weights / int32 bias / quant params
      → QUANTIZATION-PARITY gate: a numpy integer reference (bit-mirror of the emitted C)
        must match the TFLite interpreter on a held-out set
      → emit ``silken_net_audio_model.h`` — self-contained INT8 forward pass (pure C,
        gemmlowp-style integer requantize; NO TFLM/CMSIS-NN dependency), replacing the
        stub via ``__has_include`` (``firmware/soldier/main.c``).

The deployed runtime is a fixed-topology integer forward pass (docs/03_03 §4.1 of the
program doc / runtime reconciliation), NOT a TFLM interpreter — see
``tools/ml/docs/baseline_model_program.md`` §1.
"""

from __future__ import annotations

import math
from pathlib import Path

import numpy as np

from ..codegen.emit_c import c_float
from ..dsp.contract import contract_hash
from ..models import ModelConfig

# ── gemmlowp fixed-point requantize (numpy reference == the emitted C) ────────
INT32_MIN, INT32_MAX = -(1 << 31), (1 << 31) - 1


def quantize_multiplier(real_multiplier: float) -> tuple[int, int]:
    """Real multiplier in (0,1) → (int32 multiplier in [2^30,2^31), shift). gemmlowp."""
    if real_multiplier <= 0.0:
        return 0, 0
    significand, shift = math.frexp(real_multiplier)   # real = significand·2^shift, [0.5,1)
    q = round(significand * (1 << 31))
    if q == (1 << 31):
        q //= 2
        shift += 1
    if shift < -31:
        return 0, 0
    return q, shift


def _sat_round_doubling_high_mul(a: int, b: int) -> int:
    """gemmlowp SaturatingRoundingDoublingHighMul (int32×int32 → int32)."""
    if a == INT32_MIN and b == INT32_MIN:
        return INT32_MAX
    ab = a * b
    nudge = (1 << 30) if ab >= 0 else (1 - (1 << 30))
    return (ab + nudge) >> 31


def _rounding_divide_by_pot(x: int, exp: int) -> int:
    """gemmlowp RoundingDivideByPOT (round-to-nearest right shift)."""
    if exp == 0:
        return x
    mask = (1 << exp) - 1
    remainder = x & mask
    threshold = (mask >> 1) + (1 if x < 0 else 0)
    return (x >> exp) + (1 if remainder > threshold else 0)


def mul_by_quant_multiplier(x: int, q: int, shift: int) -> int:
    if shift > 0:
        x = x << shift
    high = _sat_round_doubling_high_mul(x, q)
    return _rounding_divide_by_pot(high, -shift) if shift < 0 else high


# ── fold + quantize ──────────────────────────────────────────────────────────
def fold_norm_into_fc1(model, mean, var, cfg: ModelConfig):
    """Equivalent ``Input→Dense(fc1')→ReLU→Dense(logits)`` with Normalization folded in."""
    import tensorflow as tf
    from tensorflow.keras import Model, layers

    a, c = 1.0 / np.sqrt(var), -mean / np.sqrt(var)            # z = a·x + c
    w1, b1 = model.get_layer("fc1").get_weights()             # w1 [n_mels, hidden]
    w2, b2 = model.get_layer("logits").get_weights()
    w1f = (a[:, None] * w1).astype("float32")
    b1f = (c @ w1 + b1).astype("float32")
    inp = layers.Input((cfg.n_mels,))
    h = layers.Dense(cfg.hidden, activation="relu", name="fc1")(inp)
    out = layers.Dense(cfg.n_classes, name="logits")(h)
    plain = Model(inp, out)
    plain.get_layer("fc1").set_weights([w1f, b1f])
    plain.get_layer("logits").set_weights([w2, b2])
    return plain


def to_int8_tflite(plain, representative_X, tmp_dir) -> bytes:
    """Full-integer INT8 PTQ (int8 in/out) with a real log-mel representative set."""
    import tensorflow as tf

    sm = Path(tmp_dir) / "plain_sm"
    plain.export(str(sm))
    conv = tf.lite.TFLiteConverter.from_saved_model(str(sm))
    conv.optimizations = [tf.lite.Optimize.DEFAULT]
    rep = np.asarray(representative_X, dtype=np.float32)
    conv.representative_dataset = lambda: ([rep[i:i + 1]] for i in range(len(rep)))
    conv.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS_INT8]
    conv.inference_input_type = tf.int8
    conv.inference_output_type = tf.int8
    return conv.convert()


# ── extract the int8 graph into plain arrays ─────────────────────────────────
def extract_params(tflite_bytes: bytes) -> dict:
    """Pull per-channel int8 weights / int32 bias / quant params out of the .tflite."""
    import tensorflow as tf

    itp = tf.lite.Interpreter(model_content=tflite_bytes)
    itp.allocate_tensors()
    details = itp.get_tensor_details()
    ind, outd = itp.get_input_details()[0], itp.get_output_details()[0]
    in_scale, in_zp = ind["quantization"]
    out_scale, out_zp = outd["quantization"]
    n_mels, n_classes = int(ind["shape"][-1]), int(outd["shape"][-1])

    def nscales(t):
        return len(t["quantization_parameters"]["scales"])

    # Role-based extraction (name-INdependent → robust across TF versions): the two
    # weight matrices are the only per-channel (nscales>1) int8 2-D tensors; biases are
    # int32 1-D; the fc1 ReLU output is the int8 per-tensor 2-D tensor of width `hidden`.
    weights = [t for t in details if t["dtype"] == np.int8 and len(t["shape"]) == 2 and nscales(t) > 1]
    w1t = next(t for t in weights if int(t["shape"][1]) == n_mels)        # fc1 [hidden, n_mels]
    hidden = int(w1t["shape"][0])
    w2t = next(t for t in weights if int(t["shape"][0]) == n_classes)     # fc2 [n_classes, hidden]
    biases = [t for t in details if t["dtype"] == np.int32 and len(t["shape"]) == 1]
    b1t = next(t for t in biases if int(t["shape"][0]) == hidden)
    b2t = next(t for t in biases if int(t["shape"][0]) == n_classes)
    h_out = next(t for t in details if t["dtype"] == np.int8 and nscales(t) == 1
                 and len(t["shape"]) == 2 and int(t["shape"][-1]) == hidden)
    h_scale = h_out["quantization_parameters"]["scales"][0]
    h_zp = int(h_out["quantization_parameters"]["zero_points"][0])

    def vals(t):
        return itp.get_tensor(t["index"])

    def scales(t):
        return np.asarray(t["quantization_parameters"]["scales"], dtype=np.float64)

    w1q, w2q = vals(w1t), vals(w2t)
    w1s, w2s = scales(w1t), scales(w2t)
    # per-output requantization multipliers
    m1 = [quantize_multiplier(in_scale * float(w1s[j]) / float(h_scale)) for j in range(w1q.shape[0])]
    m2 = [quantize_multiplier(float(h_scale) * float(w2s[j]) / float(out_scale)) for j in range(w2q.shape[0])]
    return {
        "in_scale": float(in_scale), "in_zp": int(in_zp),
        "fc1_w": w1q, "fc1_b": vals(b1t), "fc1_m": [q for q, _ in m1], "fc1_s": [s for _, s in m1],
        "h_zp": h_zp,
        "fc2_w": w2q, "fc2_b": vals(b2t), "fc2_m": [q for q, _ in m2], "fc2_s": [s for _, s in m2],
        "out_scale": float(out_scale), "out_zp": int(out_zp),
        "n_mels": int(w1q.shape[1]), "hidden": int(w1q.shape[0]), "n_classes": int(w2q.shape[0]),
    }


# ── numpy integer reference (BIT-MIRROR of the emitted C — the parity oracle) ─
def int_reference_logits(p: dict, x_float: np.ndarray) -> np.ndarray:
    """Run the integer forward pass on float log-mel → int8 logits (mirrors the C)."""
    inq = np.clip(np.round(x_float / p["in_scale"]) + p["in_zp"], -128, 127).astype(np.int64)
    # fc1 + relu
    h = np.empty(p["hidden"], np.int64)
    for j in range(p["hidden"]):
        acc = int(p["fc1_b"][j]) + int(np.dot(inq - p["in_zp"], p["fc1_w"][j].astype(np.int64)))
        acc = mul_by_quant_multiplier(acc, p["fc1_m"][j], p["fc1_s"][j]) + p["h_zp"]
        h[j] = min(127, max(-128, acc))      # relu = activation_min == h_zp (-128)
    # fc2
    out = np.empty(p["n_classes"], np.int64)
    for k in range(p["n_classes"]):
        acc = int(p["fc2_b"][k]) + int(np.dot(h - p["h_zp"], p["fc2_w"][k].astype(np.int64)))
        acc = mul_by_quant_multiplier(acc, p["fc2_m"][k], p["fc2_s"][k]) + p["out_zp"]
        out[k] = min(127, max(-128, acc))
    return out


def quantization_parity(p: dict, tflite_bytes: bytes, X: np.ndarray) -> dict:
    """Assert the int reference == the TFLite interpreter (argmax-exact + Δlogit)."""
    import tensorflow as tf

    itp = tf.lite.Interpreter(model_content=tflite_bytes)
    itp.allocate_tensors()
    ind, outd = itp.get_input_details()[0], itp.get_output_details()[0]
    mismatch, max_dq = 0, 0
    for i in range(len(X)):
        q = np.clip(np.round(X[i] / p["in_scale"]) + p["in_zp"], -128, 127).astype(np.int8)
        itp.set_tensor(ind["index"], q[None, :])
        itp.invoke()
        ref = int_reference_logits(p, X[i])
        tfl = itp.get_tensor(outd["index"])[0].astype(np.int64)
        max_dq = max(max_dq, int(np.max(np.abs(ref - tfl))))
        if int(np.argmax(ref)) != int(np.argmax(tfl)):
            mismatch += 1
    return {"n": len(X), "argmax_mismatch": int(mismatch), "max_abs_logit_delta": int(max_dq)}


def int8_accuracy(p: dict, X: np.ndarray, y: np.ndarray) -> float:
    pred = np.array([int(np.argmax(int_reference_logits(p, X[i]))) for i in range(len(X))])
    return float((pred == y).mean())


# ── C header emission ─────────────────────────────────────────────────────────
_CLASS_NAMES = ("SILENCE", "WIND", "CAVITATION", "CHAINSAW", "FAUNA")

_FORWARD_C = r"""/* === gemmlowp fixed-point requantize (bit-mirror of silken_ml.export) === */
static inline int32_t snam_srdhm(int32_t a, int32_t b) {
    int64_t ab, nudge;
    if (a == INT32_MIN && b == INT32_MIN) return INT32_MAX;
    ab = (int64_t)a * (int64_t)b;
    nudge = (ab >= 0) ? (int64_t)(1 << 30) : (int64_t)(1 - (1 << 30));
    return (int32_t)((ab + nudge) >> 31);
}
static inline int32_t snam_rdpot(int32_t x, int e) {
    int32_t mask, rem, thr;
    if (e == 0) return x;
    mask = (int32_t)(((int32_t)1 << e) - 1);
    rem = x & mask;
    thr = (mask >> 1) + (x < 0 ? 1 : 0);
    return (x >> e) + ((rem > thr) ? 1 : 0);
}
static inline int32_t snam_requant(int32_t x, int32_t q, int s) {
    if (s > 0) x <<= s;
    return (s < 0) ? snam_rdpot(snam_srdhm(x, q), -s) : snam_srdhm(x, q);
}
static inline int8_t snam_clamp8(int32_t v) {
    return (int8_t)(v < -128 ? -128 : (v > 127 ? 127 : v));
}

/* 40 log-mel floats -> class id [0,NUM_CLASSES); *confidence = softmax max in [0,1].
 * Heavy path is INT8 (FC -> ReLU -> FC, no-FPU friendly); only the final 5-way
 * softmax touches float (the confidence scalar). */
static inline uint8_t Run_Inference(const float* buffer, float* confidence) {
    int8_t a[MODEL_INPUT_SIZE];
    int8_t hbuf[SNAM_HIDDEN];
    int32_t logit[NUM_CLASSES];
    int i, j, k;
    uint8_t best;
    int32_t bestv;
    float sum;

    for (i = 0; i < (int)MODEL_INPUT_SIZE; i++)
        a[i] = snam_clamp8((int32_t)lrintf(buffer[i] / SNAM_IN_SCALE) + SNAM_IN_ZP);

    for (j = 0; j < SNAM_HIDDEN; j++) {
        int32_t acc = SNAM_FC1_B[j];
        for (i = 0; i < (int)MODEL_INPUT_SIZE; i++)
            acc += (int32_t)(a[i] - SNAM_IN_ZP) * (int32_t)SNAM_FC1_W[j][i];
        /* ReLU is implicit: SNAM_H_ZP is the quantized 0 (== int8 min) */
        hbuf[j] = snam_clamp8(snam_requant(acc, SNAM_FC1_M[j], SNAM_FC1_S[j]) + SNAM_H_ZP);
    }

    for (k = 0; k < (int)NUM_CLASSES; k++) {
        int32_t acc = SNAM_FC2_B[k];
        for (j = 0; j < SNAM_HIDDEN; j++)
            acc += (int32_t)(hbuf[j] - SNAM_H_ZP) * (int32_t)SNAM_FC2_W[k][j];
        acc = snam_requant(acc, SNAM_FC2_M[k], SNAM_FC2_S[k]) + SNAM_OUT_ZP;
        logit[k] = acc < -128 ? -128 : (acc > 127 ? 127 : acc);
    }

    best = 0; bestv = logit[0];
    for (k = 1; k < (int)NUM_CLASSES; k++)
        if (logit[k] > bestv) { bestv = logit[k]; best = (uint8_t)k; }
    sum = 0.0f;
    for (k = 0; k < (int)NUM_CLASSES; k++)
        sum += expf(((float)logit[k] - (float)bestv) * SNAM_OUT_SCALE);
    *confidence = 1.0f / sum;
    return best;
}
"""


def _c2d_i8(name: str, arr) -> str:
    arr = np.asarray(arr)
    rows = ["  { " + ", ".join(str(int(v)) for v in row) + " }" for row in arr]
    return (f"static const int8_t {name}[{arr.shape[0]}][{arr.shape[1]}] = {{\n"
            + ",\n".join(rows) + "\n};\n")


def _c1d(name: str, arr, ctype: str) -> str:
    flat = np.asarray(arr).ravel()
    return f"static const {ctype} {name}[{len(flat)}] = {{ " + ", ".join(str(int(v)) for v in flat) + " };\n"


def emit_header(p: dict, prov: dict) -> str:
    h = [
        # [UNI.3] emitted here so a future retrain reproduces the tag instead of dropping it
        "// SPDX-License-Identifier: AGPL-3.0-or-later\n",
        "/* silken_net_audio_model.h — AUTO-GENERATED by silken_ml.export. DO NOT EDIT.\n",
        " *\n",
        " * Baseline per-frame INT8 acoustic classifier: 40 log-mel -> 5 classes\n",
        " * (silence/wind/cavitation/chainsaw/fauna). Self-owned ESC-50 baseline that\n",
        " * UNBLOCKS FW.4 — replaces silken_net_audio_model_stub.h via __has_include.\n",
        " *\n",
        f" * Provenance: run {prov['run_id']} | float-acc {prov['float_acc']:.4f}"
        f" | int8-acc {prov['int8_acc']:.4f} | data-manifest {prov['manifest_hash']}\n",
        " *   ^ MIXED corpus: silence + cavitation are SYNTHETIC placeholders (2/5 classes) —\n",
        " *   a pipeline-integrity metric, NOT field accuracy; cavitation is NOT field-validated.\n",
        " *   Per-class validity: docs/03_03 §4.2 / tools/ml/docs/baseline_model_program.md §2.1.\n",
        f" * Quant parity vs TFLite: argmax-exact, max|d logit|={prov['parity']['max_abs_logit_delta']}"
        f" (n={prov['parity']['n']}).\n",
        f" * Log-mel contract hash {contract_hash()} (docs/03_03 §3.4) — RETRAIN if it changes.\n",
        " *\n",
        " * Runtime: self-contained integer forward pass (gemmlowp requantize); NO TFLM /\n",
        " * CMSIS-NN dependency (docs/03_03 runtime reconciliation; weights -> Flash const,\n",
        " * activations -> stack, ~0 .bss). Program: tools/ml/docs/baseline_model_program.md.\n",
        " */\n",
        "#ifndef SILKEN_NET_AUDIO_MODEL_H\n#define SILKEN_NET_AUDIO_MODEL_H\n\n",
        "#include <stdint.h>\n#include <math.h>\n\n",
        "/* === Class contract (matches silken_net_audio_model_stub.h) ============= */\n",
    ]
    for i, name in enumerate(_CLASS_NAMES[:p["n_classes"]]):
        h.append(f"#define ML_CLASS_{name:<15} {i}u\n")
    h.append(f"#define NUM_CLASSES              {p['n_classes']}u\n")
    h.append(f"#define MODEL_INPUT_SIZE         {p['n_mels']}u\n")
    h.append(f"#define SNAM_HIDDEN              {p['hidden']}\n")
    ws = p["n_mels"] + p["hidden"] + p["n_classes"] * 4
    h.append(f"#define TENSOR_ARENA_SIZE        {ws}u"
             "  /* int8 activations + logits — STACK; weights are const (Flash) -> ~0 .bss */\n\n")
    h.append("/* === Quantization parameters ========================================== */\n")
    h.append(f"#define SNAM_IN_SCALE   {c_float(p['in_scale'])}\n")
    h.append(f"#define SNAM_IN_ZP      {p['in_zp']}\n")
    h.append(f"#define SNAM_H_ZP       ({p['h_zp']})\n")
    h.append(f"#define SNAM_OUT_ZP     {p['out_zp']}\n")
    h.append(f"#define SNAM_OUT_SCALE  {c_float(p['out_scale'])}\n\n")
    h.append("/* === Weights (Flash / .rodata) ======================================== */\n")
    h.append(_c2d_i8("SNAM_FC1_W", p["fc1_w"]))
    h.append(_c1d("SNAM_FC1_B", p["fc1_b"], "int32_t"))
    h.append(_c1d("SNAM_FC1_M", p["fc1_m"], "int32_t"))
    h.append(_c1d("SNAM_FC1_S", p["fc1_s"], "int32_t"))
    h.append(_c2d_i8("SNAM_FC2_W", p["fc2_w"]))
    h.append(_c1d("SNAM_FC2_B", p["fc2_b"], "int32_t"))
    h.append(_c1d("SNAM_FC2_M", p["fc2_m"], "int32_t"))
    h.append(_c1d("SNAM_FC2_S", p["fc2_s"], "int32_t"))
    h.append("\n")
    h.append(_FORWARD_C)
    h.append("\n#endif /* SILKEN_NET_AUDIO_MODEL_H */\n")
    return "".join(h)


def emit_golden(p: dict, X: np.ndarray, idxs=None, n_golden: int = 12) -> str:
    nm, nc = p["n_mels"], p["n_classes"]
    if idxs is None:
        # Guarantee per-PREDICTED-class coverage: round-robin so the n_golden cap never
        # drops a whole class (the earlier index-sorted truncation could → no cavitation
        # frame). The golden's cls is the model prediction, so the host smoke tests get
        # >=1 frame per class the device actually emits (cavitation/chainsaw → 03_03 §8 #6/#7).
        preds = np.array([int(np.argmax(int_reference_logits(p, X[i]))) for i in range(len(X))])
        rng = np.random.default_rng(0)
        per_class = [
            [int(v) for v in rng.choice(ci, min(3, len(ci)), replace=False)]
            for c in range(nc) for ci in (np.where(preds == c)[0],) if len(ci)
        ]
        idxs = [g[rank] for rank in range(max((len(g) for g in per_class), default=0))
                for g in per_class if rank < len(g)][:n_golden]
    out = [
        # [UNI.3] emitted here so a future retrain reproduces the tag instead of dropping it
        "// SPDX-License-Identifier: AGPL-3.0-or-later\n",
        "/* silken_net_audio_model_golden.h — AUTO-GENERATED by silken_ml.export. DO NOT EDIT.\n",
        " * Golden frames (input -> int reference logits + class) for the host model test.\n */\n",
        "#ifndef SILKEN_NET_AUDIO_MODEL_GOLDEN_H\n#define SILKEN_NET_AUDIO_MODEL_GOLDEN_H\n\n#include <stdint.h>\n\n",
        f"#define SNAM_GOLDEN_COUNT {len(idxs)}\n",
        f"#define SNAM_GOLDEN_N_MELS {nm}\n#define SNAM_GOLDEN_N_CLASSES {nc}\n\n",
        f"typedef struct {{ float input[{nm}]; int32_t logits[{nc}]; uint8_t cls; }} snam_golden_t;\n\n",
        "static const snam_golden_t SNAM_GOLDEN[SNAM_GOLDEN_COUNT] = {\n",
    ]
    for i in idxs:
        lg = int_reference_logits(p, X[i])
        inp = ", ".join(c_float(float(v)) for v in X[i])
        lgs = ", ".join(str(int(v)) for v in lg)
        out.append(f"  {{ {{ {inp} }}, {{ {lgs} }}, {int(np.argmax(lg))} }},\n")
    out.append("};\n\n#endif /* SILKEN_NET_AUDIO_MODEL_GOLDEN_H */\n")
    return "".join(out)


def footprint(p: dict) -> dict:
    w = int(np.asarray(p["fc1_w"]).size + np.asarray(p["fc2_w"]).size)
    aux = (len(p["fc1_b"]) + len(p["fc1_m"]) + len(p["fc1_s"])
           + len(p["fc2_b"]) + len(p["fc2_m"]) + len(p["fc2_s"])) * 4
    return {"flash_weights_bytes": w + aux, "int8_weights_bytes": w,
            "stack_activation_bytes": p["n_mels"] + p["hidden"] + p["n_classes"] * 4,
            "bss_arena_bytes": 0}


def build_from_run(run_dir, header_out="firmware/soldier/silken_net_audio_model.h",
                   golden_out="firmware/test/silken_net_audio_model_golden.h", n_golden=12) -> dict:
    """Run → fold → INT8 → extract → PARITY GATE → emit header + golden. Returns a summary."""
    import json

    import tensorflow as tf

    run = Path(run_dir)
    model = tf.keras.models.load_model(run / "model.keras")
    w1, _ = model.get_layer("fc1").get_weights()
    cfg = ModelConfig(n_mels=int(w1.shape[0]), hidden=int(w1.shape[1]),
                      n_classes=int(model.get_layer("logits").get_weights()[0].shape[1]))
    st = np.load(run / "norm_stats.npz")
    plain = fold_norm_into_fc1(model, st["mean"], st["variance"], cfg)
    tfl = to_int8_tflite(plain, np.load(run / "representative.npz")["X"], run)
    (run / "model_int8.tflite").write_bytes(tfl)
    p = extract_params(tfl)
    d = np.load(run / "parity_test.npz")
    x_te, y_te = d["X"], d["y"]
    par = quantization_parity(p, tfl, x_te)
    if par["argmax_mismatch"] != 0 or par["max_abs_logit_delta"] > 1:
        raise RuntimeError(f"QUANTIZATION-PARITY gate FAILED: {par}")

    repro = json.loads((run / "reproducibility.json").read_text())
    prov = {"run_id": repro["run_id"], "float_acc": repro["metrics"]["accuracy"],
            "int8_acc": int8_accuracy(p, x_te, y_te),
            "manifest_hash": repro["data_manifest_hash"], "parity": par}

    Path(header_out).write_text(emit_header(p, prov), encoding="utf-8")
    Path(golden_out).write_text(emit_golden(p, x_te, n_golden=n_golden), encoding="utf-8")
    fp = footprint(p)
    (run / "export_report.json").write_text(json.dumps(
        {"parity": par, "footprint": fp, "int8_acc": prov["int8_acc"],
         "provenance": {k: v for k, v in prov.items() if k != "parity"}}, indent=2, default=float))
    return {"header": header_out, "golden": golden_out, "parity": par, "footprint": fp,
            "int8_acc": prov["int8_acc"], "tflite_bytes": len(tfl)}
