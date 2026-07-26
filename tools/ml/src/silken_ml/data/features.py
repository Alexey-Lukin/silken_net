# SPDX-License-Identifier: AGPL-3.0-or-later
"""Clip → device-domain per-frame log-mel features — THE SAME contract as the device.

Pipeline mirrors the firmware ``audio_buffer[]``: AC signal → (peak-ref) → +DC bias
(→ ``[0,1)``-ish, like ``raw_adc/4095``) → ``silken_ml.dsp.logmel_librosa.compute_logmel``
(per-frame DC-removal + periodic Hann + RFFT + HTK mel + ln; docs/03_03 §3.4). Using the
canonical oracle guarantees **train ≡ device** feature parity (it is == stdlib == C).
"""

from __future__ import annotations

import numpy as np

from ..dsp import logmel_librosa as oracle
from ..dsp.contract import CONTRACT
from .config import DataConfig


def frame_ac_rms(ac: np.ndarray, cfg: DataConfig) -> np.ndarray:
    """Per-frame RMS of the (per-frame DC-removed) AC signal, aligned to the log-mel frames."""
    ac = np.asarray(ac, dtype=np.float64)
    n_fft, hop = CONTRACT.n_fft, CONTRACT.hop
    out, i = [], 0
    while i + n_fft <= len(ac):
        f = ac[i:i + n_fft]
        out.append(float(np.sqrt(np.mean((f - f.mean()) ** 2))))
        i += hop
    return np.asarray(out, dtype=np.float64)


def clip_to_features(ac, cfg: DataConfig, normalize_peak: bool = True):
    """AC clip → ``(logmel [n_frames, 40] float32, ac_rms [n_frames] float64)``."""
    ac = np.asarray(ac, dtype=np.float64)
    if normalize_peak:
        peak = float(np.max(np.abs(ac))) if ac.size else 0.0
        if peak > 1e-9:
            ac = ac / peak * cfg.real_peak
    x = np.clip(ac + cfg.dc_bias, 0.0, 1.0 - 1e-7)        # device domain [0,1)
    logmel = oracle.compute_logmel(x, CONTRACT)           # [n_frames, 40] float64
    rms = frame_ac_rms(ac, cfg)
    n = min(len(logmel), len(rms))
    return np.asarray(logmel[:n], dtype=np.float32), rms[:n]
