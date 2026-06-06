"""Parity gate: pure-stdlib oracle ≡ canonical librosa oracle (tol 1e-6).

This is the bridge that lets the dependency-free local path stand in for the
heavy training-side oracle. Skipped automatically if the [oracle] extra
(numpy + librosa) is not installed — it runs in the conda `silken_ml` env
(CI: ml_smoke.yml).
"""

import math
import random

import pytest

pytest.importorskip("numpy")
pytest.importorskip("librosa")

from silken_ml.dsp import logmel_librosa as Lib
from silken_ml.dsp import logmel_stdlib as S
from silken_ml.dsp.contract import CONTRACT

TOL = 1e-6


def _frames():
    n, sr = CONTRACT.n_fft, CONTRACT.sr
    rnd = random.Random(1234)
    cases = [[0.0] * n, [0.5] * n]
    cases += [[rnd.random() for _ in range(n)] for _ in range(8)]
    for bin_k in (8, 33, 100, 200):
        f = bin_k * sr / n
        cases.append([0.5 + 0.4 * math.sin(2 * math.pi * f * i / sr) for i in range(n)])
    return cases


def test_mel_filterbank_parity():
    s = S.mel_filterbank()
    lib = Lib.mel_filterbank()
    assert lib.shape == (CONTRACT.n_mels, CONTRACT.n_bins)
    maxerr = max(abs(s[m][k] - float(lib[m][k]))
                 for m in range(CONTRACT.n_mels) for k in range(CONTRACT.n_bins))
    assert maxerr < TOL, f"mel-bank parity error {maxerr}"


def test_logmel_parity():
    maxerr = 0.0
    for frame in _frames():
        a = S.compute_logmel_frame(frame)
        b = Lib.compute_logmel_frame(frame)
        maxerr = max(maxerr, max(abs(a[i] - float(b[i])) for i in range(CONTRACT.n_mels)))
    assert maxerr < TOL, f"log-mel parity error {maxerr}"
