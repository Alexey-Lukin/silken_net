"""Canonical librosa log-mel oracle (training-side) — ``docs/03_03 §3.4``.

This is the *heavy* path (numpy + librosa, conda ``silken_ml`` env). It is the
artifact a future ML partner would train on, and the parity test asserts it is
byte-equal to the pure-stdlib oracle (tol 1e-6) — so the dependency-free local
path is provably the same feature math.

It reproduces the §3.4 reference EXACTLY, including the **per-frame DC removal**
that ``librosa.feature.melspectrogram`` omits (the latent-bug fix): we frame
manually, subtract each frame's mean, apply the *periodic* Hann, RFFT, power,
HTK mel-bank (norm=None), and natural log with floor.
"""

from __future__ import annotations

from .contract import CONTRACT, LogMelContract


def _require_librosa():
    try:
        import librosa
        import numpy as np
    except ImportError as exc:  # pragma: no cover - exercised only without the extra
        raise ImportError(
            "logmel_librosa needs the [oracle] extra (numpy + librosa). "
            "Install the conda env: `micromamba env create -f tools/ml/environment.yml`."
        ) from exc
    return librosa, np


def mel_filterbank(c: LogMelContract = CONTRACT):
    """``librosa.filters.mel(..., htk=True, norm=None)`` → ``[n_mels, n_bins]``."""
    librosa, _ = _require_librosa()
    return librosa.filters.mel(
        sr=c.sr, n_fft=c.n_fft, n_mels=c.n_mels,
        fmin=c.fmin, fmax=c.fmax, htk=c.htk, norm=None,
    )


def compute_logmel(signal, c: LogMelContract = CONTRACT):
    """``[n_frames, n_mels]`` log-mel — the canonical §3.4 pipeline (numpy array)."""
    librosa, np = _require_librosa()
    audio = np.asarray(signal, dtype=np.float64)

    mel_fb = mel_filterbank(c)                                        # [40, 257]
    win = librosa.filters.get_window("hann", c.n_fft, fftbins=True)   # periodic
    frames = librosa.util.frame(audio, frame_length=c.n_fft, hop_length=c.hop)
    frames = frames - frames.mean(axis=0, keepdims=True)             # DC per-frame
    power = np.abs(np.fft.rfft(frames * win[:, None], axis=0)) ** 2  # [257, n]
    logmel = np.log(mel_fb @ power + c.log_floor)                    # [40, n]
    return logmel.T                                                   # [n, 40]


def compute_logmel_frame(audio, c: LogMelContract = CONTRACT):
    """One ``n_fft``-sample frame → ``n_mels`` log-mel (parity with the stdlib API)."""
    _, np = _require_librosa()
    audio = np.asarray(audio, dtype=np.float64)
    if audio.shape != (c.n_fft,):
        raise ValueError(f"frame must be {c.n_fft} samples, got {audio.shape}")
    return compute_logmel(audio, c)[0]
