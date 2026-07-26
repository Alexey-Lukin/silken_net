# SPDX-License-Identifier: AGPL-3.0-or-later
"""Log-mel DSP front-end — FW.25 / ``docs/03_03 §3.4``.

``contract`` is the single Python home for the numeric contract (mirror of the
SSOT in ``docs/03_03 §3.4``). ``logmel_stdlib`` is the dependency-free oracle
(the fast local path); ``logmel_librosa`` is the canonical training-side oracle.
A parity test asserts the two are byte-equal (tol 1e-6).
"""

from .contract import CONTRACT, LogMelContract, contract_hash
