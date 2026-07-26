# SPDX-License-Identifier: AGPL-3.0-or-later
"""Codegen determinism + the committed-firmware-headers drift gate (stdlib only)."""

from silken_ml.codegen import emit_c


def test_committed_headers_match_contract():
    # The committed firmware/common/logmel_*.h must equal a fresh regen.
    assert emit_c.check_all(emit_c.default_out_dir()) == 0


def test_generation_is_deterministic():
    assert emit_c.gen_hann() == emit_c.gen_hann()
    assert emit_c.gen_mel_bank() == emit_c.gen_mel_bank()
    assert emit_c.gen_golden() == emit_c.gen_golden()


def test_headers_stamp_contract_hash():
    h = emit_c.contract_hash()
    for gen in (emit_c.gen_hann, emit_c.gen_mel_bank, emit_c.gen_golden):
        assert h in gen()


def test_float_literal_roundtrips_float32():
    # %.9g round-trips through float32 (what the C compiler does parsing "…f"),
    # NOT through double — so compare at float32 resolution.
    for x in (0.0, 1.0, 0.270546883, -13.8155, 1e-6):
        lit = emit_c.c_float(x)
        assert lit.endswith("f")
        parsed = float(lit[:-1])
        assert emit_c.f32(parsed) == emit_c.f32(x)
