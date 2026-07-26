# SPDX-License-Identifier: AGPL-3.0-or-later
"""Contract invariants + drift tripwire (stdlib only)."""

import dataclasses

from silken_ml.dsp.contract import CONTRACT, LogMelContract, contract_hash

# Pinned hash — mirrors docs/03_03 §3.4 + firmware/common/logmel_contract.h.
# If this fails, the contract changed: update ALL THREE homes together and
# regenerate the firmware tables (`python -m silken_ml.codegen.emit_c`).
PINNED_HASH = "0cd21eb3c2d89ac6"


def test_contract_invariants():
    assert CONTRACT.n_bins == CONTRACT.n_fft // 2 + 1
    assert CONTRACT.n_mels == 40
    assert CONTRACT.fmax == CONTRACT.sr / 2
    assert CONTRACT.mel_norm == "none"
    assert CONTRACT.dc_remove is True


def test_contract_hash_pinned():
    assert contract_hash() == PINNED_HASH


def test_contract_hash_changes_on_edit():
    bumped = dataclasses.replace(CONTRACT, n_mels=41)
    assert contract_hash(bumped) != contract_hash(CONTRACT)


def test_bad_contract_rejected():
    import pytest
    with pytest.raises(AssertionError):
        LogMelContract(n_bins=999)  # violates n_fft//2+1
