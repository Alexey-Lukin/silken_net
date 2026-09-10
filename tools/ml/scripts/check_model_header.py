#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Freshness check for the AUTO-GENERATED firmware model header [FW.4].

Needs the `silken_ml` conda env (TensorFlow: `extract_params` reads the tflite through
`tf.lite.Interpreter`), so it rides `ml_smoke.yml`, not the stdlib firmware job — that
was measured before building, not assumed. Mirrors `check_firmware_tables.py`, which is
the same shape for the log-mel tables.

    python tools/ml/scripts/check_model_header.py
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from silken_ml.export import check_committed

if __name__ == "__main__":
    raise SystemExit(check_committed())
