# SPDX-License-Identifier: AGPL-3.0-or-later
"""Training + evaluation for the baseline per-frame acoustic classifier.

Enterprise conventions (explicitly NOT the MVP shape of ``lib/tasks/ai_train.rake``):
config-driven, seed-everything, reproducibility manifest ``{data_manifest_hash,
code_git_sha, env_hash, config, metrics}``, real eval (stratified test, per-class
precision/recall/F1, confusion matrix, confidence CALIBRATION → FW.18 thresholds),
and a model registry with provenance. See ``tools/ml/docs/baseline_model_program.md`` §3.
"""

from __future__ import annotations

import hashlib
import json
import os
import platform
import random
import subprocess
import time
from dataclasses import asdict, dataclass, field
from pathlib import Path

import numpy as np

from ..data import DataConfig, build_dataset, build_manifest, manifest_hash
from ..data.config import CLASS_NAMES
from ..models import ModelConfig, build_model


@dataclass(frozen=True)
class TrainConfig:
    data: DataConfig = field(default_factory=DataConfig)
    model: ModelConfig = field(default_factory=ModelConfig)
    epochs: int = 40
    batch_size: int = 256
    lr: float = 1.0e-3
    seed: int = 20_260_612
    registry_dir: str = "tools/ml/models/registry"


# ── reproducibility helpers ──────────────────────────────────────────────────
def seed_everything(seed: int) -> None:
    os.environ["PYTHONHASHSEED"] = str(seed)
    random.seed(seed)
    np.random.seed(seed)  # noqa: NPY002 — global legacy seed; Generators used explicitly elsewhere
    import tensorflow as tf

    tf.random.set_seed(seed)


def _git_sha() -> str:
    try:
        return subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
    except Exception:  # pragma: no cover - git absent
        return "unknown"


def _env_descriptor() -> tuple[str, str]:
    import sklearn
    import tensorflow as tf

    s = (f"py{platform.python_version()}-tf{tf.__version__}"
         f"-np{np.__version__}-sk{sklearn.__version__}")
    return s, hashlib.sha256(s.encode()).hexdigest()[:16]


# ── evaluation (real metrics, not just accuracy) ─────────────────────────────
def _ece(conf: np.ndarray, correct: np.ndarray, n_bins: int = 15) -> float:
    """Expected Calibration Error — confidence must mean what it says (FW.18)."""
    edges = np.linspace(0.0, 1.0, n_bins + 1)
    ece, n = 0.0, len(conf)
    for i in range(n_bins):
        m = (conf > edges[i]) & (conf <= edges[i + 1])
        if m.sum():
            ece += abs(correct[m].mean() - conf[m].mean()) * m.sum() / n
    return float(ece)


def _conf_at_precision(score: np.ndarray, pos: np.ndarray, target: float) -> float:
    """Lowest one-vs-rest confidence threshold whose precision ≥ target (FW.18 hint)."""
    order = np.argsort(-score)
    p = pos[order].astype(float)
    prec = np.cumsum(p) / np.arange(1, len(p) + 1)
    ok = np.where(prec >= target)[0]
    return float(score[order][ok[-1]]) if len(ok) else 1.0


def evaluate(model, X, y, class_names) -> dict:
    import tensorflow as tf
    from sklearn.metrics import classification_report, confusion_matrix

    logits = model.predict(X, batch_size=512, verbose=0)
    probs = tf.nn.softmax(logits).numpy()
    pred, conf = probs.argmax(1), probs.max(1)
    labels = list(range(len(class_names)))
    return {
        "accuracy": float((pred == y).mean()),
        "report": classification_report(y, pred, labels=labels, target_names=class_names,
                                        output_dict=True, zero_division=0),
        "confusion": confusion_matrix(y, pred, labels=labels).tolist(),
        "ece": _ece(conf, (pred == y).astype(float)),
        "fw18_conf_at_p90": {int(c): _conf_at_precision(probs[:, c], y == c, 0.90)
                             for c in (2, 3)},  # cavitation, chainsaw
    }


# ── train ────────────────────────────────────────────────────────────────────
def train(cfg: TrainConfig | None = None):
    """Train, evaluate, and register the baseline model. Returns ``(run_dir, metrics)``."""
    import tensorflow as tf
    from sklearn.utils.class_weight import compute_class_weight

    cfg = cfg if cfg is not None else TrainConfig()
    seed_everything(cfg.seed)
    ds, ds_meta = build_dataset(cfg.data)
    (xtr, ytr), (xva, yva), (xte, yte) = ds["train"], ds["val"], ds["test"]

    mean, var = xtr.mean(0), xtr.var(0) + 1e-6
    model = build_model(mean, var, cfg.model)
    model.compile(
        optimizer=tf.keras.optimizers.Adam(cfg.lr),
        loss=tf.keras.losses.SparseCategoricalCrossentropy(from_logits=True),
        metrics=["accuracy"],
    )
    classes = np.arange(cfg.model.n_classes)
    cw = compute_class_weight("balanced", classes=classes, y=ytr)
    model.fit(xtr, ytr, validation_data=(xva, yva), epochs=cfg.epochs,
              batch_size=cfg.batch_size, class_weight=dict(enumerate(cw)), verbose=0)

    metrics = evaluate(model, xte, yte, list(CLASS_NAMES))

    # provenance + registry
    manifest = build_manifest(cfg.data)
    env_str, env_hash = _env_descriptor()
    run_id = time.strftime("%Y%m%dT%H%M%S")
    run_dir = Path(cfg.registry_dir) / run_id
    run_dir.mkdir(parents=True, exist_ok=True)
    model.save(run_dir / "model.keras")
    np.savez(run_dir / "norm_stats.npz", mean=mean, variance=var)
    np.savez(run_dir / "parity_test.npz", X=xte, y=yte)          # export QUANT-parity set
    rep_idx = np.random.default_rng(cfg.seed).choice(len(xtr), min(512, len(xtr)), replace=False)
    np.savez(run_dir / "representative.npz", X=xtr[rep_idx])     # PTQ representative set
    (run_dir / "data_manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True))
    (run_dir / "reproducibility.json").write_text(json.dumps({
        "run_id": run_id,
        "data_manifest_hash": manifest_hash(manifest),
        "config": asdict(cfg),
        "code_git_sha": _git_sha(),
        "env": env_str,
        "env_hash": env_hash,
        "dataset_meta": ds_meta,
        "metrics": {k: v for k, v in metrics.items() if k != "report"},
        "report": metrics["report"],
    }, indent=2, default=float))
    return run_dir, metrics
