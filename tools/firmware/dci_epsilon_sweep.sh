#!/usr/bin/env bash
# tools/firmware/dci_epsilon_sweep.sh — [FW.31] Gate L: |Δz|-розподіл
# справжній mruby-VM ↔ справжній контракт у CRuby на N зчеплених кейсів.
#
# Закриває статистичну половину lab-протоколу 03_04 §7.1 БЕЗ заліза:
#   - ARM↔x86 плече вже бітово-нульове (FW.55 QEMU byte-parity, ISA-рівень;
#     кремнієвий хвіст = той самий one-command FW.55 дамп);
#   - тут міряється ДРУГЕ плече DCI — mruby-VM (пристрій) ↔ CRuby (сервер):
#     кожна сторона ланцюжить ВЛАСНИЙ хвіст (модель warm-chaining DCI),
#     кейс-генератор бітово дзеркалить firmware/sim/parity_core.h.
#
#   tools/firmware/dci_epsilon_sweep.sh           # N=10000 (дефолт §7.1)
#   N=200 tools/firmware/dci_epsilon_sweep.sh     # швидка перевірка
#
# Вихід: розподіл |Δz| (max, p50/p99/p99.9/p99.99), бітово-точні збіги,
# категоричні розбіжності payload (очікувано 0). Не CI-гейт — відтворюваний
# інструмент рішення про ε (verdict проти DEFAULT_DCI_EPSILON=0.001).
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
MRUBY="$REPO/firmware/extern/mruby"
BUILD="$MRUBY/build/host-min"
OUT="$REPO/firmware/build-sim"
N="${N:-10000}"
CC="${CC:-cc}"

mkdir -p "$OUT"

if [ ! -f "$BUILD/lib/libmruby.a" ]; then
  echo "▶ [FW.31] building minimal-gembox host mruby…"
  ( cd "$MRUBY" && SILKEN_MIN_HOST=1 MRUBY_CONFIG="$REPO/firmware/mruby/build_config.rb" rake -j4 >/dev/null )
fi

# Той самий host_main/parity_core, що й голден FW.55 — лише N більший.
# MRB_DEFS — дзеркало SILKEN_MIN_GEMS (One-Home: firmware/mruby/build_config.rb).
echo "▶ [FW.31] mruby-VM sweep build (N=$N)…"
"$CC" -std=c11 -O2 -Wall -Wextra \
  -DPARITY_N_CASES="$N" \
  -DMRB_NO_STDIO -DMRB_CONSTRAINED_BASELINE_PROFILE -DMRB_NO_BOXING \
  -I"$MRUBY/include" -I"$BUILD/include" \
  -I"$REPO/firmware/common" -I"$REPO/firmware/sim" \
  -o "$OUT/dci_sweep_vm" "$REPO/firmware/sim/host_main.c" \
  "$BUILD/lib/libmruby.a" -lm

echo "▶ [FW.31] mruby-VM run…"
"$OUT/dci_sweep_vm" > "$OUT/dci_sweep_vm.txt"
grep -q "PARITY-COMPLETE" "$OUT/dci_sweep_vm.txt" || { echo "❌ VM-прогін без маркера"; exit 1; }

echo "▶ [FW.31] CRuby (справжній bio_contract.rb) + |Δz|-розподіл…"
ruby "$REPO/tools/firmware/dci_epsilon_sweep.rb" "$OUT/dci_sweep_vm.txt"
