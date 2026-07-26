# SPDX-License-Identifier: AGPL-3.0-or-later
"""Assemble the 5-class per-frame dataset with a CLIP-level, stratified, seeded split.

**Anti-leakage rule:** frames from one clip NEVER straddle the train/val/test boundary —
clips are split first (stratified by class), then expanded to frames. Classes are balanced
by capping frames per class (train only). Returns ``float32 X[N,40]`` + ``int64 y[N]`` per
split, plus split provenance (counts per class).
"""

from __future__ import annotations

import csv
from pathlib import Path

import numpy as np

from . import features as F
from . import synthetic
from .config import ESC50_CLASS_TARGETS, NUM_CLASSES, DataConfig


def _esc50_clips(cfg: DataConfig):
    """Yield ``(label, ac_signal)`` for the sourced ESC-50 clips (resampled to ``cfg.sr``)."""
    import librosa

    root = Path(cfg.esc50_root)
    target_to_class = {t: cls for cls, ts in ESC50_CLASS_TARGETS.items() for t in ts}
    with open(root / "meta" / "esc50.csv", newline="") as f:
        items = [(target_to_class[int(r["target"])], root / "audio" / r["filename"])
                 for r in csv.DictReader(f) if int(r["target"]) in target_to_class]
    for label, wav in sorted(items, key=lambda it: it[1].name):
        ac, _ = librosa.load(str(wav), sr=cfg.sr, mono=True)
        yield label, np.asarray(ac, dtype=np.float64)


def _synth_clips(cfg: DataConfig):
    for i in range(cfg.n_silence_clips):
        yield 0, synthetic.gen_silence(i, cfg)
    for i in range(cfg.n_cavitation_clips):
        yield 2, synthetic.gen_cavitation(i, cfg)


def _clip_records(cfg: DataConfig):
    """All clips → list of ``(label, logmel[n,40], ac_rms[n])``."""
    recs = []
    for label, ac in _esc50_clips(cfg):
        recs.append((label, *F.clip_to_features(ac, cfg, normalize_peak=True)))
    for label, ac in _synth_clips(cfg):
        # silence kept faint (no peak-normalize); cavitation normalized like the real classes.
        recs.append((label, *F.clip_to_features(ac, cfg, normalize_peak=(label != 0))))
    return recs


def build_dataset(cfg: DataConfig | None = None):
    """Build ``{split: (X, y)}`` + metadata from the pinned corpus."""
    cfg = cfg if cfg is not None else DataConfig()
    rng = np.random.default_rng(cfg.seed)
    recs = _clip_records(cfg)

    # clip-level stratified split (frames inherit their clip's split → no leakage).
    by_class: dict[int, list[int]] = {}
    for ci, (label, _, _) in enumerate(recs):
        by_class.setdefault(label, []).append(ci)
    split = dict.fromkeys(range(len(recs)), "train")
    for idxs in by_class.values():
        idxs = list(idxs)
        rng.shuffle(idxs)
        n = len(idxs)
        n_test = round(n * cfg.test_frac)
        n_val = round(n * cfg.val_frac)
        for ci in idxs[:n_test]:
            split[ci] = "test"
        for ci in idxs[n_test:n_test + n_val]:
            split[ci] = "val"

    # expand to frames; gate non-silence frames by AC energy.
    buckets = {s: {"X": [], "y": []} for s in ("train", "val", "test")}
    for ci, (label, logmel, rms) in enumerate(recs):
        keep = np.ones(len(logmel), bool) if label == 0 else (rms >= cfg.frame_ac_rms_gate)
        b = buckets[split[ci]]
        b["X"].append(logmel[keep])
        b["y"].append(np.full(int(keep.sum()), label, np.int64))

    out = {}
    for s, b in buckets.items():
        X = np.concatenate(b["X"]) if b["X"] else np.zeros((0, 40), np.float32)
        y = np.concatenate(b["y"]) if b["y"] else np.zeros((0,), np.int64)
        if s == "train" and len(y):  # balance: cap frames per class
            keep_idx = []
            for c in range(NUM_CLASSES):
                ci_idx = np.where(y == c)[0]
                if len(ci_idx) > cfg.max_frames_per_class:
                    ci_idx = rng.choice(ci_idx, cfg.max_frames_per_class, replace=False)
                keep_idx.append(ci_idx)
            keep_idx = np.concatenate(keep_idx)
            rng.shuffle(keep_idx)
            X, y = X[keep_idx], y[keep_idx]
        out[s] = (X.astype(np.float32), y.astype(np.int64))

    meta = {
        "n_clips": len(recs),
        "split_counts": {s: len(out[s][1]) for s in out},
        "class_counts": {s: {int(c): int((out[s][1] == c).sum()) for c in range(NUM_CLASSES)}
                         for s in out},
        "config_hash": cfg.hash(),
    }
    return out, meta
