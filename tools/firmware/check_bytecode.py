# SPDX-License-Identifier: AGPL-3.0-or-later
"""[FW.46 · FW.66 S4] Light stdlib drift gate for the committed mruby bytecode mirrors
(firmware/common/*_bytecode.h — one per on-device contract era).

Each mirror declares its own `Sources:` (compile order) and a `sources sha256:` stamp of
their concatenation; this gate recomputes the hash from those files. Catches "edited a
contract source (or the shared metabolic_core.rb) but forgot to regenerate" without
needing mrbc — runs in the LIGHT ci.yml › firmware_test job (gcc + python3, no mruby
build). The source list is read from the stamp, so this file holds no second copy of
the target list: a header that went missing is the DEEP gate's catch.

The DEEP regenerate-and-diff check (needs the pinned mruby/mrbc) lives in
`tools/firmware/gen_bytecode.sh --check` (ci.yml › firmware_arm_build).

    python3 tools/firmware/check_bytecode.py
"""
import hashlib
import re
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
# Both eras must be present — an empty glob would make this gate vacuous.
EXPECTED = {"lorenz_bytecode.h", "ccm_bytecode.h"}


def check(hdr: Path) -> bool:
    text = hdr.read_text()
    srcs = re.search(r"^ \* Sources:\s+(.+)$", text, re.M)
    stamp = re.search(r"sources sha256:\s*([0-9a-f]{64})", text)
    if not srcs or not stamp:
        print(f"❌ [FW.46] {hdr.name}: no Sources/sha256 stamp — run tools/firmware/gen_bytecode.sh")
        return False
    files = [REPO / s for s in srcs.group(1).split()]
    missing = [f for f in files if not f.exists()]
    if missing:
        print(f"❌ [FW.46] {hdr.name}: declared source(s) absent: {', '.join(str(m.relative_to(REPO)) for m in missing)}")
        return False
    actual = hashlib.sha256(b"".join(f.read_bytes() for f in files)).hexdigest()
    if actual != stamp.group(1):
        print(f"❌ [FW.46] {srcs.group(1)} changed but {hdr.name} not regenerated")
        print(f"   sources sha256: {actual}")
        print(f"   stamped:        {stamp.group(1)}")
        print("   → run tools/firmware/gen_bytecode.sh")
        return False
    print(f"✅ [FW.46] {hdr.name} stamp matches {srcs.group(1)} ({actual[:12]}…)")
    return True


def main() -> int:
    headers = sorted((REPO / "firmware/common").glob("*_bytecode.h"))
    absent = EXPECTED - {h.name for h in headers}
    if absent:
        print(f"❌ [FW.46] missing {', '.join(sorted(absent))} — run tools/firmware/gen_bytecode.sh")
        return 1
    results = [check(h) for h in headers]   # every mirror reports — a generator would stop at the first ❌
    return 0 if all(results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
