"""Committed corpus manifest — pins the dataset for reproducibility (sha256, not a folder).

ESC-50 real files are pinned by ``sha256`` + license; the synthetic classes are pinned by
their generator ``seed`` + ``version`` (reproducible without storing audio). A model is then
reproducible from ``manifest_hash``, not a mutable ``data/raw/`` tree.
"""

from __future__ import annotations

import csv
import hashlib
import json
from pathlib import Path

from .config import CLASS_NAMES, ESC50_CLASS_TARGETS, DataConfig

ESC50_LICENSE = "CC BY-NC 3.0 — ESC-50, K. J. Piczak (github.com/karolpiczak/ESC-50)"
SYNTH_GEN_VERSION = "1.0.0"


def _sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65_536), b""):
            h.update(chunk)
    return h.hexdigest()


def build_manifest(cfg: DataConfig) -> dict:
    """Scan ESC-50 meta for the sourced categories → a pinned, sorted corpus manifest."""
    root = Path(cfg.esc50_root)
    target_to_class = {t: cls for cls, ts in ESC50_CLASS_TARGETS.items() for t in ts}
    esc50: list[dict] = []
    with open(root / "meta" / "esc50.csv", newline="") as f:
        for row in csv.DictReader(f):
            tgt = int(row["target"])
            if tgt in target_to_class:
                label = target_to_class[tgt]
                esc50.append({
                    "filename": row["filename"],
                    "sha256": _sha256(root / "audio" / row["filename"]),
                    "category": row["category"],
                    "esc50_target": tgt,
                    "label": label,
                    "label_name": CLASS_NAMES[label],
                })
    esc50.sort(key=lambda r: r["filename"])
    return {
        "schema": "silken_ml.baseline_corpus/1",
        "source": "ESC-50 @ github.com/karolpiczak/ESC-50 (master)",
        "esc50_license": ESC50_LICENSE,
        "esc50_files": esc50,
        "synthetic": {
            "silence": {"label": 0, "n_clips": cfg.n_silence_clips, "seed": cfg.seed + 101,
                        "generator": "gen_silence", "version": SYNTH_GEN_VERSION},
            "cavitation": {"label": 2, "n_clips": cfg.n_cavitation_clips, "seed": cfg.seed + 202,
                           "generator": "gen_cavitation", "version": SYNTH_GEN_VERSION,
                           "note": "physics-motivated placeholder; not field-valid (docs/03_03 §4.2)"},
        },
        "config_hash": cfg.hash(),
    }


def manifest_hash(manifest: dict) -> str:
    """Stable 16-hex digest of the manifest — the corpus provenance key."""
    return hashlib.sha256(json.dumps(manifest, sort_keys=True).encode("utf-8")).hexdigest()[:16]


def write_manifest(manifest: dict, path) -> None:
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    Path(path).write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def load_manifest(path) -> dict:
    return json.loads(Path(path).read_text(encoding="utf-8"))
