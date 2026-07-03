"""Synthetic generators for the two classes with no honest open-data analog.

- **silence(0)** — low-amplitude broadband noise: genuinely quiet, lands near the log
  floor after the contract pipeline.
- **cavitation(2)** — physics-motivated xylem acoustic-emission: sparse, brief, broadband
  high-frequency CLICKS (5–8 kHz decaying bursts; docs/03_03 §4.2 "5–20 kHz impulsive",
  band-limited to Nyquist 8 kHz @ 16 kHz). This is a **labelled PLACEHOLDER** — it makes
  the class-2 smoke test real and exercises the 5-class pipeline, but is NOT field-valid;
  it is replaced by lab AE recordings + the partner model.

Generators return zero-mean AC (the device-domain DC bias is added in ``features.py``),
are deterministic given the config seed, and produce ``clip_seconds`` of ``sr``-Hz audio.
"""

from __future__ import annotations

import numpy as np

from .config import DataConfig


def _rng(seed: int, idx: int) -> np.random.Generator:
    return np.random.default_rng((seed * 1_000_003 + idx) & 0xFFFF_FFFF_FFFF_FFFF)


def gen_silence(idx: int, cfg: DataConfig) -> np.ndarray:
    """One synthetic silence clip — faint zero-mean broadband noise."""
    n = int(cfg.sr * cfg.clip_seconds)
    r = _rng(cfg.seed + 101, idx)
    return (r.standard_normal(n) * cfg.silence_ac_rms).astype(np.float64)


def gen_cavitation(idx: int, cfg: DataConfig) -> np.ndarray:
    """One synthetic cavitation clip — sparse decaying 5–8 kHz clicks.

    5–8 kHz is an audible-band PROXY bounded by the 16 kHz Nyquist, NOT the physical
    acoustic-emission frequency of xylem cavitation (ultrasonic 25–150 kHz; Tyree &
    Dixon 1983). This trains a low-frequency structural-slough proxy, not true AE
    detection — the current chain cannot observe the real signal. See docs 03_03 §4.2;
    true ultrasonic detection needs a dedicated high-rate channel (UNI.11 / v3).
    """
    n = int(cfg.sr * cfg.clip_seconds)
    r = _rng(cfg.seed + 202, idx)
    sig = np.zeros(n, dtype=np.float64)
    n_events = int(r.integers(20, 60))                 # sparse clicks across the 5 s
    for _ in range(n_events):
        dur = int(r.integers(48, 160))                 # ~3–10 ms burst
        start = int(r.integers(0, n - dur))
        t = np.arange(dur)
        f = r.uniform(5000.0, 8000.0)                  # high-freq AE, within Nyquist
        decay = np.exp(-t / (dur / 4.0))
        burst = np.sin(2.0 * np.pi * f * t / cfg.sr) * decay
        sig[start:start + dur] += burst * r.uniform(0.5, 1.0)
    return sig
