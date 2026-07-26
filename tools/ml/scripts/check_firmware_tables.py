#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Stdlib-only drift check for firmware/common/logmel_*.h.

Runs in the LIGHT firmware CI job (`ci.yml › firmware_test`) — no conda, no
librosa, no install. A thin wrapper over the codegen `--check` so the firmware
path stays dependency-free while still proving the committed tables match the
contract (docs/03_03 §3.4).

    python3 tools/ml/scripts/check_firmware_tables.py
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from silken_ml.codegen import emit_c

if __name__ == "__main__":
    raise SystemExit(emit_c.main(["--check"]))
