"""SilkenNet ML engineering toolkit (``silken_ml``).

The "set up once" home for the project's machine-learning surface. Domains:

- ``dsp/``     — log-mel feature front-end (FW.25). The canonical contract +
                 two byte-equal oracles (librosa + pure-stdlib) + the C codegen
                 that emits the committed ``firmware/common/logmel_*.h`` tables.
- ``data/``    — dataset loading / splits / manifest (scaffold).
- ``models/``  — model architectures (scaffold).
- ``train/``   — training + evaluation: metrics / confusion / calibration (scaffold).
- ``export/``  — INT8 TFLite → ``silken_net_audio_model.h`` (scaffold).

SSOT contract home: ``docs/03_03 §3.4``. Operating manual: ``tools/ml/README.md``.

Design invariant — *three implementations, one definition, proven equal*:
librosa (training oracle) ≡ pure-stdlib (fast local oracle, no numpy) ≡ C
``Compute_LogMel`` (on-device). Golden vectors are generated once and asserted
across all three.
"""

__version__ = "0.1.0"
