#!/usr/bin/env bash
# tools/firmware/run_bytecode_vm.sh — [FW.46] Build + run the minimal-VM bytecode
# harness (firmware/test/test_bytecode_vm.c). Builds the minimal-gembox host
# mruby on demand, links the harness against it, and runs the committed bytecode
# through mrb_load_irep — proving the minimal gembox executes bio_contract.rb.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
MRUBY="$REPO/firmware/extern/mruby"
BUILD="$MRUBY/build/host-min"
CC="${CC:-cc}"

if [ ! -f "$BUILD/lib/libmruby.a" ]; then
  echo "[FW.46] building minimal-gembox host mruby…"
  ( cd "$MRUBY" && SILKEN_MIN_HOST=1 MRUBY_CONFIG="$REPO/firmware/mruby/build_config.rb" rake -j4 >/dev/null )
fi

bin="$(mktemp -u)"
# NB: -I$BUILD/include is required for the build-generated mruby/presym/id.h.
"$CC" -std=c11 -O2 -Wall \
  -I"$MRUBY/include" -I"$BUILD/include" -I"$REPO/firmware/common" \
  -o "$bin" "$REPO/firmware/test/test_bytecode_vm.c" \
  "$BUILD/lib/libmruby.a" -lm
"$bin"; rc=$?
rm -f "$bin"
exit $rc
