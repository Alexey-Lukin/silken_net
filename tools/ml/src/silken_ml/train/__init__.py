"""Training + evaluation — SCAFFOLD (needs a dataset + TensorFlow, deferred).

Enterprise conventions (explicitly *not* the MVP shape of
``lib/tasks/ai_train.rake``, which fits-on-all-data + Marshal-dumps with no eval):

  - Config-driven (dataclass/YAML); every hyperparameter explicit, no magic numbers.
  - Seed everything; emit a reproducibility manifest per run:
    ``{data_manifest_hash, code_git_sha, env_hash, config, metrics}``.
  - Real eval: stratified train/val/test, accuracy + per-class precision/recall/F1,
    confusion matrix, and confidence CALIBRATION — the FW.18 WARNING/CRITICAL
    softmax thresholds (``docs/03_03 §5``) are only meaningful if calibrated.
  - Model registry: ``models/registry/<version>/`` with weights + a provenance
    digest (the SHA256 idea from ``ai_train.rake``, done properly + versioned).
"""

from __future__ import annotations


def train(*_args, **_kwargs):  # pragma: no cover - scaffold
    raise NotImplementedError("train module is a scaffold — see module docstring")
