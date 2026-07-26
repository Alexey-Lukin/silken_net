# SPDX-License-Identifier: AGPL-3.0-or-later
"""Pure-stdlib log-mel oracle — the dependency-free reference (``math``/``cmath``).

This is the *fast local* path: it runs anywhere (no numpy/librosa), generates the
golden vectors the C consumes, and is asserted byte-equal to the librosa oracle
(``logmel_librosa``) at tol 1e-6 in CI. It implements ``docs/03_03 §3.4`` exactly:

    DC-remove (per-frame mean) → periodic Hann → RFFT (naive DFT, 257 bins)
    → power re²+im² → HTK mel-bank (norm=None) → ln(·+1e-6)

The naive O(N²) DFT is deliberate: it is *obviously correct* (no FFT-butterfly
bug surface), and with N=512 and a handful of golden frames it is plenty fast.
The C side swaps in radix-2 (host) / ``arm_rfft_fast_f32`` (target) and matches
these same goldens at tol 1e-3.
"""

from __future__ import annotations

import math
from functools import cache

from .contract import CONTRACT, LogMelContract


# ── Mel scale (HTK, closed form — matches librosa htk=True) ──────────────────
def hz_to_mel_htk(f: float) -> float:
    return 2595.0 * math.log10(1.0 + f / 700.0)


def mel_to_hz_htk(m: float) -> float:
    return 700.0 * (10.0 ** (m / 2595.0) - 1.0)


@cache
def mel_filterbank(c: LogMelContract = CONTRACT) -> tuple[tuple[float, ...], ...]:
    """``n_mels × n_bins`` triangular HTK filter bank, ``norm=None``.

    Byte-identical to ``librosa.filters.mel(sr, n_fft, n_mels, fmin, fmax,
    htk=True, norm=None)``: peak-1.0 triangles, no Slaney area scaling.
    """
    fftfreqs = [k * c.sr / c.n_fft for k in range(c.n_bins)]
    min_mel, max_mel = hz_to_mel_htk(c.fmin), hz_to_mel_htk(c.fmax)
    mel_pts = [min_mel + (max_mel - min_mel) * i / (c.n_mels + 1)
               for i in range(c.n_mels + 2)]
    hz_pts = [mel_to_hz_htk(m) for m in mel_pts]
    fdiff = [hz_pts[i + 1] - hz_pts[i] for i in range(len(hz_pts) - 1)]

    fb = []
    for m in range(c.n_mels):
        row = []
        for k in range(c.n_bins):
            lower = (fftfreqs[k] - hz_pts[m]) / fdiff[m]
            upper = (hz_pts[m + 2] - fftfreqs[k]) / fdiff[m + 1]
            row.append(max(0.0, min(lower, upper)))
        fb.append(tuple(row))
    return tuple(fb)


@cache
def periodic_hann(n: int) -> tuple[float, ...]:
    """Periodic Hann (``fftbins=True``): ``0.5 - 0.5*cos(2πk/N)``, denom N."""
    return tuple(0.5 - 0.5 * math.cos(2.0 * math.pi * k / n) for k in range(n))


@cache
def _twiddle(n: int) -> tuple[tuple[tuple[float, float], ...], ...]:
    """Precomputed ``(cos, sin)`` for the naive RFFT — ``[n_bins][n]``."""
    nb = n // 2 + 1
    return tuple(
        tuple((math.cos(-2.0 * math.pi * k * i / n),
               math.sin(-2.0 * math.pi * k * i / n)) for i in range(n))
        for k in range(nb)
    )


def _rfft_power(frame: list[float]) -> list[float]:
    """Real DFT → power spectrum ``re²+im²`` for bins ``0..N/2`` (no 1/N)."""
    n = len(frame)
    tw = _twiddle(n)
    power = []
    for k in range(n // 2 + 1):
        re = im = 0.0
        row = tw[k]
        for i, x in enumerate(frame):
            c, s = row[i]
            re += x * c
            im += x * s
        power.append(re * re + im * im)
    return power


def compute_logmel_frame(audio: list[float], c: LogMelContract = CONTRACT) -> list[float]:
    """One ``n_fft``-sample frame → ``n_mels`` log-mel features (the C contract)."""
    if len(audio) != c.n_fft:
        raise ValueError(f"frame must be {c.n_fft} samples, got {len(audio)}")

    # 1. DC-remove (per-frame mean) — see §3.4 (audio is [0,1), DC ≈ 0.5).
    mean = math.fsum(audio) / c.n_fft
    # 2. periodic Hann window.
    win = periodic_hann(c.n_fft)
    windowed = [(audio[i] - mean) * win[i] for i in range(c.n_fft)]
    # 3. RFFT → power.
    power = _rfft_power(windowed)
    # 4. mel-bank (sparse mat-mul) → 5. ln(·+floor).
    fb = mel_filterbank(c)
    out = []
    for m in range(c.n_mels):
        row = fb[m]
        acc = math.fsum(row[k] * power[k] for k in range(c.n_bins))
        out.append(math.log(acc + c.log_floor))
    return out


def frame_signal(signal: list[float], c: LogMelContract = CONTRACT) -> list[list[float]]:
    """Split a longer signal into ``hop``-spaced ``n_fft`` frames (drop remainder)."""
    frames = []
    i = 0
    while i + c.n_fft <= len(signal):
        frames.append(signal[i:i + c.n_fft])
        i += c.hop
    return frames


def compute_logmel(signal: list[float], c: LogMelContract = CONTRACT) -> list[list[float]]:
    """``[n_frames][n_mels]`` log-mel for a multi-frame signal."""
    return [compute_logmel_frame(f, c) for f in frame_signal(signal, c)]
