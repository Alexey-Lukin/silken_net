#!/usr/bin/env bash
# firmware/scripts/qemu_parity.sh — [FW.55] біт-parity mruby Lorenz:
# host-голден ↔ реальний Cortex-M4 код-шлях на qemu-system-arm (mps2-an386).
#
# Той самий committed-байткод (lorenz_bytecode.h), той самий minimal-gembox
# mruby; кейси зчеплені (вихід N → вхід N+1). Гейт = byte-exact diff дампів
# C-ліній (StatusByte + IEEE-754 біти x/y/z). Закриває FW.7/FW.19 residual
# «ARM↔x86 Float drift» до тонкого silicon-confirm (один прогін на платі).
#
#   firmware/scripts/qemu_parity.sh            # локально (skip, якщо немає qemu)
#   REQUIRE_QEMU=1 firmware/scripts/qemu_parity.sh   # CI: відсутній qemu = fail
#
# Залежності: gcc (host), arm-none-eabi-gcc (PATH / ARM_PREFIX /
# firmware/.toolchain/*/bin), qemu-system-arm (PATH / QEMU_BIN), ruby+rake
# для разової побудови mruby-бібліотек (далі кешуються в build-дирах mruby).
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
MRUBY="$REPO/firmware/extern/mruby"
HOST_BUILD="$MRUBY/build/host-min"
ARM_BUILD="$MRUBY/build/arm-none-eabi"
OUT="$REPO/firmware/build-sim"
mkdir -p "$OUT"

CPU_FLAGS="-mcpu=cortex-m4 -mfpu=fpv4-sp-d16 -mfloat-abi=hard -mthumb"

# ── Інструменти ─────────────────────────────────────────────────────────
CC_HOST="${CC:-cc}"

arm_gcc="${ARM_PREFIX:-arm-none-eabi-}gcc"
if ! command -v "$arm_gcc" >/dev/null 2>&1; then
  local_tc="$(ls -d "$REPO"/firmware/.toolchain/*/bin 2>/dev/null | head -1 || true)"
  if [ -n "$local_tc" ] && [ -x "$local_tc/arm-none-eabi-gcc" ]; then
    arm_gcc="$local_tc/arm-none-eabi-gcc"
  else
    echo "❌ [FW.55] arm-none-eabi-gcc не знайдено (PATH / ARM_PREFIX / firmware/.toolchain)"
    exit 1
  fi
fi

QEMU="${QEMU_BIN:-qemu-system-arm}"
if ! command -v "$QEMU" >/dev/null 2>&1; then
  if [ "${REQUIRE_QEMU:-0}" = "1" ]; then
    echo "❌ [FW.55] qemu-system-arm відсутній, а REQUIRE_QEMU=1 (CI-режим)"
    exit 1
  fi
  echo "⚠️  [FW.55] qemu-system-arm відсутній — QEMU-нога ПРОПУЩЕНА (локальний режим)."
  QEMU=""
fi

# ── mruby бібліотеки (разова побудова, далі — кеш) ──────────────────────
if [ ! -f "$HOST_BUILD/lib/libmruby.a" ]; then
  echo "▶ [FW.55] building host-min mruby…"
  ( cd "$MRUBY" && SILKEN_MIN_HOST=1 MRUBY_CONFIG="$REPO/firmware/mruby/build_config.rb" rake -j4 >/dev/null )
fi
if [ -n "$QEMU" ] || [ "${BUILD_ARM:-1}" = "1" ]; then
  if [ ! -f "$ARM_BUILD/lib/libmruby.a" ]; then
    echo "▶ [FW.55] building arm-none-eabi mruby…"
    arm_bin="$(dirname "$arm_gcc")"
    ( cd "$MRUBY" && PATH="$arm_bin:$PATH" SILKEN_ARM_BUILD=1 \
        MRUBY_CONFIG="$REPO/firmware/mruby/build_config.rb" rake -j4 >/dev/null )
  fi
fi

INC=(-I"$MRUBY/include" -I"$REPO/firmware/common" -I"$REPO/firmware/sim")

# ── Host-голден ─────────────────────────────────────────────────────────
echo "▶ [FW.55] host golden…"
"$CC_HOST" -std=c11 -O2 -Wall -Wextra "${INC[@]}" -I"$HOST_BUILD/include" \
  -o "$OUT/parity_host" "$REPO/firmware/sim/host_main.c" \
  "$HOST_BUILD/lib/libmruby.a" -lm
"$OUT/parity_host" > "$OUT/host.txt"
grep -q "PARITY-COMPLETE" "$OUT/host.txt" || { echo "❌ host-прогін без маркера"; exit 1; }

# ── ARM-нога: збірка завжди (link-перевірка), запуск — якщо є qemu ──────
echo "▶ [FW.55] arm-none-eabi build…"
"$arm_gcc" $CPU_FLAGS -std=gnu11 -O2 -Wall -Wextra \
  -ffunction-sections -fdata-sections -nostartfiles \
  "${INC[@]}" -I"$ARM_BUILD/include" \
  -T "$REPO/firmware/sim/qemu_m4/mps2_an386.ld" -Wl,--gc-sections \
  -o "$OUT/parity_arm.elf" \
  "$REPO/firmware/sim/qemu_m4/main.c" \
  "$REPO/firmware/sim/qemu_m4/startup.c" \
  "$REPO/firmware/sim/qemu_m4/syscalls.c" \
  "$ARM_BUILD/lib/libmruby.a" -lm

if [ -z "$QEMU" ]; then
  echo "✅ [FW.55] host-голден OK + ARM .elf зібрано (QEMU-ногу доведе CI)"
  exit 0
fi

echo "▶ [FW.55] qemu-system-arm mps2-an386…"
timeout 180 "$QEMU" -M mps2-an386 -nographic -semihosting \
  -kernel "$OUT/parity_arm.elf" < /dev/null | tr -d '\r' > "$OUT/arm.txt"
grep -q "PARITY-COMPLETE" "$OUT/arm.txt" || { echo "❌ ARM-прогін без маркера"; tail -5 "$OUT/arm.txt"; exit 1; }

# ── Вердикт: byte-exact по C-лініях ─────────────────────────────────────
grep '^C' "$OUT/host.txt" > "$OUT/host_cases.txt"
grep '^C' "$OUT/arm.txt"  > "$OUT/arm_cases.txt"
if ! diff -u "$OUT/host_cases.txt" "$OUT/arm_cases.txt" > "$OUT/parity.diff"; then
  echo "❌ [FW.55] ARM↔x86 БІТОВА РОЗБІЖНІСТЬ — це знахідка (FW.7/FW.19), дивись:"
  head -20 "$OUT/parity.diff"
  exit 1
fi
n_cases="$(wc -l < "$OUT/host_cases.txt" | tr -d ' ')"
echo "✅ [FW.55] біт-parity ARM(M4/QEMU) ≡ host: $n_cases зчеплених кейсів, byte-exact"
