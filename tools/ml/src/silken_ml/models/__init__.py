"""Model architectures — SCAFFOLD (no trained model yet).

Path B (``docs/03_03 §3.4`` / §4): a small 2D-CNN over log-mel features (40 bands
per frame; 156-frame mean‖std aggregate for the fauna class). The exact topology
comes from training; the firmware consumes ONLY the INT8-exported
``silken_net_audio_model.h``. Output: 5 classes
(silence / wind / cavitation / chainsaw / fauna).
"""

from __future__ import annotations


def build_model(*_args, **_kwargs):  # pragma: no cover - scaffold
    raise NotImplementedError("models module is a scaffold — see module docstring")
