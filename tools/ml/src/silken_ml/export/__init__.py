"""INT8 TFLite → ``silken_net_audio_model.h`` export — SCAFFOLD (deferred).

Pipeline (when a trained model exists):

  keras/SavedModel
    → ``TFLiteConverter`` INT8 post-training quantization (representative dataset
      drawn from real log-mel features — the ``dsp`` front-end)
    → QUANTIZATION-PARITY gate: float vs INT8 outputs within tolerance on a
      held-out set (the INT8 analogue of the DSP golden-vector parity)
    → emit ``silken_net_audio_model.h`` (quantized weights + inline ``Run_Inference``
      + measured ``TENSOR_ARENA_SIZE``), replacing the stub via ``__has_include``
      (``firmware/soldier/main.c``).

Then FW.4: measure the real arena (``arm-none-eabi-size``) and uncomment the
Phase-1.5 call-site. TensorFlow/tflite are added to ``environment.yml`` at that point.
"""

from __future__ import annotations


def export_tflite_int8(*_args, **_kwargs):  # pragma: no cover - scaffold
    raise NotImplementedError("export module is a scaffold — see module docstring")
