"""Unit tests for the INT8 export fixed-point arithmetic (no TensorFlow needed).

These exercise the gemmlowp requantize helpers that the emitted C
``silken_net_audio_model.h`` mirrors bit-for-bit. The full train→tflite→parity
path lives behind TF (ml_smoke); this is the light, always-runnable guard on the
most error-prone math.
"""

from __future__ import annotations

import pytest

from silken_ml.export import mul_by_quant_multiplier, quantize_multiplier


@pytest.mark.parametrize("m", [0.5, 0.25, 0.1, 0.0034, 0.0005, 0.9, 0.123456, 1.5, 2.5])
@pytest.mark.parametrize("x", [0, 1, -1, 100, -100, 1000, -1000, 12345, -54321, 1 << 20, -(1 << 20)])
def test_requantize_approximates_real_multiply(x, m):
    """MultiplyByQuantizedMultiplier(x, QuantizeMultiplier(m)) ≈ round(x·m) within 1 LSB."""
    q, s = quantize_multiplier(m)
    got = mul_by_quant_multiplier(x, q, s)
    assert abs(got - round(x * m)) <= 1, (x, m, got, round(x * m))


def test_quantize_multiplier_is_normalized():
    for m in [0.5, 0.1, 0.0005, 0.9]:
        q, s = quantize_multiplier(m)
        assert (1 << 30) <= q < (1 << 31)   # significand in [0.5, 1) → q in [2^30, 2^31)
        assert s <= 0                        # m < 1 → right shift only


def test_quantize_multiplier_degenerate():
    assert quantize_multiplier(0.0) == (0, 0)
    assert quantize_multiplier(-1.0) == (0, 0)


def test_requantize_zero_multiplier_is_zero():
    assert mul_by_quant_multiplier(123456, 0, 0) == 0
