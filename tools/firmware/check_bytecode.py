#!/usr/bin/env python3
"""[FW.46] Light stdlib drift gate for firmware/common/lorenz_bytecode.h.

Recomputes sha256(firmware/bio_contracts/bio_contract.rb) and compares it to
the `bio_contract.rb sha256:` stamp inside the committed bytecode mirror.
Catches "edited bio_contract.rb but forgot to regenerate the bytecode" without
needing mrbc — runs in the LIGHT ci.yml › firmware_test job (gcc + python3, no
mruby build).

The DEEP regenerate-and-diff check (needs the pinned mruby/mrbc) lives in
`tools/firmware/gen_bytecode.sh --check` (ci.yml › firmware_arm_build).

    python3 tools/firmware/check_bytecode.py
"""
import hashlib
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SRC = REPO / "firmware/bio_contracts/bio_contract.rb"
HDR = REPO / "firmware/common/lorenz_bytecode.h"


def main() -> int:
    if not HDR.exists():
        print(f"❌ [FW.46] missing {HDR.relative_to(REPO)} — run tools/firmware/gen_bytecode.sh")
        return 1
    actual = hashlib.sha256(SRC.read_bytes()).hexdigest()
    m = re.search(r"bio_contract\.rb sha256:\s*([0-9a-f]{64})", HDR.read_text())
    if not m:
        print(f"❌ [FW.46] no sha256 stamp in {HDR.name}")
        return 1
    stamped = m.group(1)
    if actual != stamped:
        print("❌ [FW.46] bio_contract.rb changed but lorenz_bytecode.h not regenerated")
        print(f"   source sha256: {actual}")
        print(f"   stamped:       {stamped}")
        print("   → run tools/firmware/gen_bytecode.sh")
        return 1
    print(f"✅ [FW.46] lorenz_bytecode.h stamp matches bio_contract.rb ({actual[:12]}…)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
