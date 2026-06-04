"""Log-mel feature contract — **mirror** of the SSOT in ``docs/03_03 §3.4``.

One-Home rule: the *values* are owned by ``docs/03_03 §3.4``. This file and the
C mirror ``firmware/common/logmel_contract.h`` restate them for code; all three
must agree. ``contract_hash()`` is the drift tripwire — the codegen stamps it
into every generated header, and CI re-derives it, so a silent edit on one side
turns a gate red.
"""

from __future__ import annotations

import hashlib
import json
from dataclasses import asdict, dataclass


@dataclass(frozen=True)
class LogMelContract:
    """Frozen numeric contract for the 512-sample → 40-band log-mel front-end."""

    sr: int = 16_000          # sample rate (Hz) — TIM2 metronome
    n_fft: int = 512          # frame length (= 32 ms @ 16 kHz) = one DMA block
    hop: int = 512            # no overlap → 156 frames / 5 s fauna window
    n_bins: int = 257         # n_fft // 2 + 1 (RFFT bins, incl. DC + Nyquist)
    n_mels: int = 40          # per-frame model input (MODEL_INPUT_SIZE)
    fmin: float = 50.0        # mel low edge (Hz)
    fmax: float = 8000.0      # mel high edge (Hz) = Nyquist @ 16 kHz
    htk: bool = True          # HTK mel scale: 2595*log10(1+f/700) (closed form)
    mel_norm: str = "none"    # raw triangular filters (NO Slaney area norm)
    power: float = 2.0        # |X|^2 = re^2 + im^2 (no 1/N scaling)
    log_floor: float = 1e-6   # ln(mel + floor) — natural log, floor vs log(0)
    window: str = "hann_periodic"  # 0.5-0.5*cos(2*pi*n/N); NOT symmetric (N-1)
    dc_remove: bool = True    # subtract per-frame mean BEFORE windowing

    def __post_init__(self) -> None:
        # Cheap invariants — catch a fat-finger edit before it reaches the C side.
        assert self.n_bins == self.n_fft // 2 + 1, "n_bins must be n_fft//2+1"
        assert 0.0 <= self.fmin < self.fmax <= self.sr / 2, "need 0 <= fmin < fmax <= Nyquist"
        assert self.mel_norm == "none", "contract fixes raw (norm=None) triangles"


CONTRACT = LogMelContract()


def contract_hash(contract: LogMelContract = CONTRACT) -> str:
    """Stable 16-hex-char SHA256 of the contract — the cross-side drift tripwire."""
    payload = json.dumps(asdict(contract), sort_keys=True).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()[:16]
