"""Dataset loading / splits / manifest for the baseline acoustic model.

Enterprise conventions honoured here (so the first real corpus slots in without
re-litigating process):

  - Audio lives under ``data/raw/`` (gitignored). A COMMITTED ``data/manifest.json``
    pins the corpus: per-file ``sha256`` + source + license + label (ESC-50), and the
    generator ``seed`` + ``version`` for the synthetic classes. A model is reproducible
    from its manifest hash, not a mutable folder.
  - Deterministic, STRATIFIED, CLIP-level train/val/test split (seeded). Frames from one
    clip never straddle the boundary — splitting at the frame level silently leaks.
  - Interim corpus: ESC-50 (wind/chainsaw + animal fauna proxy) + synthetic silence /
    cavitation. Field-valid replacement: the Cherkasy Soundscape Library (docs/03_03 §10).

See ``tools/ml/docs/baseline_model_program.md`` for the program.
"""

from __future__ import annotations

from .config import CLASS_NAMES, ESC50_CLASS_TARGETS, NUM_CLASSES, DataConfig
from .dataset import build_dataset
from .manifest import build_manifest, load_manifest, manifest_hash, write_manifest

__all__ = [
    "CLASS_NAMES",
    "ESC50_CLASS_TARGETS",
    "NUM_CLASSES",
    "DataConfig",
    "build_dataset",
    "build_manifest",
    "load_manifest",
    "manifest_hash",
    "write_manifest",
]
