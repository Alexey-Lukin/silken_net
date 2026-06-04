"""Property tests for the pure-stdlib log-mel oracle (no heavy deps)."""

import math
import random

from silken_ml.dsp import logmel_stdlib as L
from silken_ml.dsp.contract import CONTRACT

FLOOR = math.log(CONTRACT.log_floor)  # ln(1e-6) ≈ -13.8155


def test_silence_is_log_floor():
    out = L.compute_logmel_frame([0.0] * CONTRACT.n_fft)
    assert len(out) == CONTRACT.n_mels
    assert all(abs(v - FLOOR) < 1e-9 for v in out)


def test_dc_offset_removed():
    # A constant signal carries only DC; per-frame DC removal must collapse it
    # to silence. This is the regression test for the §3.4 DC-removal fix.
    out = L.compute_logmel_frame([0.5] * CONTRACT.n_fft)
    assert all(abs(v - FLOOR) < 1e-9 for v in out)


def test_tone_localizes_energy():
    sr, n = CONTRACT.sr, CONTRACT.n_fft
    f = 64 * sr / n  # 2 kHz — lands at FFT bin 64
    tone = [0.5 + 0.4 * math.sin(2 * math.pi * f * i / sr) for i in range(n)]
    out = L.compute_logmel_frame(tone)
    assert max(out) > FLOOR + 5.0            # real energy, not the floor
    assert min(out) < max(out) - 5.0          # concentrated, not flat


def test_mel_bank_shape_and_sparsity():
    fb = L.mel_filterbank()
    assert len(fb) == CONTRACT.n_mels
    assert all(len(r) == CONTRACT.n_bins for r in fb)
    nnz = sum(1 for r in fb for w in r if w > 0)
    assert 0 < nnz < CONTRACT.n_mels * CONTRACT.n_bins


def test_periodic_hann_endpoints():
    w = L.periodic_hann(CONTRACT.n_fft)
    assert abs(w[0]) < 1e-12                   # periodic Hann starts at 0
    assert abs(w[CONTRACT.n_fft // 2] - 1.0) < 1e-9   # peak at N/2
    assert w[1] > 0.0                          # not all-zero


def test_power_spectrum_nonnegative_finite():
    rnd = random.Random(7)
    frame = [rnd.random() for _ in range(CONTRACT.n_fft)]
    mean = sum(frame) / CONTRACT.n_fft
    win = L.periodic_hann(CONTRACT.n_fft)
    wd = [(frame[i] - mean) * win[i] for i in range(CONTRACT.n_fft)]
    power = L._rfft_power(wd)
    assert len(power) == CONTRACT.n_bins
    assert all(p >= 0.0 and math.isfinite(p) for p in power)
