# SPDX-License-Identifier: AGPL-3.0-or-later
"""Configuration for the baseline acoustic dataset + model — config-driven, no magic numbers.

Every knob lives here so a run is reproducible from a single frozen object (its ``hash()``
is stamped into the run manifest). See ``tools/ml/docs/baseline_model_program.md`` §2–3.
Class IDs MUST match ``firmware/soldier/silken_net_audio_model_stub.h`` (``ML_CLASS_*``).
"""

from __future__ import annotations

import hashlib
import json
from dataclasses import asdict, dataclass

# Class IDs — single source of truth shared with the firmware stub (ML_CLASS_*).
CLASS_NAMES = ("silence", "wind", "cavitation", "chainsaw", "fauna")
NUM_CLASSES = 5

# ESC-50 category *targets* that honestly source each class (docs/03_03 §4.2 + ESC-50 meta).
# silence(0) + cavitation(2) have NO honest open-data analog → synthetic (see synthetic.py).
ESC50_CLASS_TARGETS = {
    1: (16,),           # wind
    3: (41,),           # chainsaw
    4: (13, 14, 4, 7),  # fauna proxy: crickets, chirping_birds, frog, insects
}


@dataclass(frozen=True)
class DataConfig:
    """Frozen dataset/feature configuration (hashed into the reproducibility manifest)."""

    esc50_root: str = "tools/ml/data/raw/ESC-50-master"
    sr: int = 16_000              # device sample rate (log-mel contract, docs/03_03 §3.4)
    clip_seconds: float = 5.0     # ESC-50 clip length == fauna window (156 frames)

    # device-domain mapping: AC → peak-ref → +DC bias (mirrors audio_buffer[] in [0,1)).
    real_peak: float = 0.4        # golden-vector convention (0.5 + 0.4·signal)
    dc_bias: float = 0.5

    # synthetic class sizes (clips) — balance against the 40-clip ESC-50 real classes.
    n_silence_clips: int = 40
    n_cavitation_clips: int = 40
    silence_ac_rms: float = 0.004  # genuinely quiet → near the log floor

    # per-frame energy gate: drop sub-threshold frames from NON-silence classes
    # (a silent gap inside a chainsaw clip must not be labelled "chainsaw").
    frame_ac_rms_gate: float = 0.02

    # balance: cap frames per class (train only) so no class dominates the loss.
    max_frames_per_class: int = 4_000

    # split (by CLIP, stratified, seeded — frames never leak across the boundary).
    val_frac: float = 0.15
    test_frac: float = 0.15
    seed: int = 20_260_612

    def hash(self) -> str:
        """Stable 16-hex digest of the config — provenance key for a run."""
        payload = json.dumps(asdict(self), sort_keys=True).encode("utf-8")
        return hashlib.sha256(payload).hexdigest()[:16]
