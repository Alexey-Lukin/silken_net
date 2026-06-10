#!/usr/bin/env bash
# firmware/scripts/qemu_logmel.sh — [FW.4] QEMU-M4 нога log-mel DSP:
# CMSIS-шлях Compute_LogMel (arm_rfft_fast_f32, soft-float = ABI WLE5 без FPU)
# на qemu-system-arm (mps2-an386): golden-parity (спільне ядро з host-ctest,
# sim/logmel_parity_core.h) + stack high-water навколо чистих викликів.
#
#   firmware/scripts/qemu_logmel.sh                  # локально (skip без qemu)
#   REQUIRE_QEMU=1 firmware/scripts/qemu_logmel.sh   # CI: відсутній qemu = fail
#
# Збірка — через FW.46 cross-CMake (firmware/build): той самий silken_common +
# CMSIS-DSP, що міряє `size`. Залежності: arm-none-eabi-gcc (PATH / ARM_PREFIX /
# firmware/.toolchain), cmake, qemu-system-arm.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD="$REPO/firmware/build"
OUT="$REPO/firmware/build-sim"
mkdir -p "$OUT"

# ── Інструменти (та сама логіка пошуку, що qemu_parity.sh) ───────────────
arm_gcc="${ARM_PREFIX:-arm-none-eabi-}gcc"
CMAKE_TC_ARGS=()
if ! command -v "$arm_gcc" >/dev/null 2>&1; then
  local_tc="$(ls -d "$REPO"/firmware/.toolchain/*/bin 2>/dev/null | head -1 || true)"
  if [ -n "$local_tc" ] && [ -x "$local_tc/arm-none-eabi-gcc" ]; then
    arm_gcc="$local_tc/arm-none-eabi-gcc"
    CMAKE_TC_ARGS+=(-DARM_TOOLCHAIN_PATH="$local_tc")
  else
    echo "❌ [FW.4] arm-none-eabi-gcc не знайдено (PATH / ARM_PREFIX / firmware/.toolchain)"
    exit 1
  fi
fi

QEMU="${QEMU_BIN:-qemu-system-arm}"
if ! command -v "$QEMU" >/dev/null 2>&1; then
  if [ "${REQUIRE_QEMU:-0}" = "1" ]; then
    echo "❌ [FW.4] qemu-system-arm відсутній, а REQUIRE_QEMU=1 (CI-режим)"
    exit 1
  fi
  echo "⚠️  [FW.4] qemu-system-arm відсутній — QEMU-нога ПРОПУЩЕНА (локальний режим)."
  QEMU=""
fi

# ── Cross-CMake збірка (захист від застарілого hard-float кешу) ──────────
if [ -f "$BUILD/CMakeCache.txt" ] && ! grep -q -- '-mfloat-abi=soft' "$BUILD/CMakeCache.txt"; then
  echo "♻️  [FW.4] кеш зібрано не-soft-float ABI — переконфігуровую начисто"
  rm -rf "$BUILD"
fi
if [ ! -f "$BUILD/CMakeCache.txt" ]; then
  cmake -B "$BUILD" -S "$REPO/firmware" \
    -DCMAKE_TOOLCHAIN_FILE="$REPO/firmware/cmake/arm-none-eabi.cmake" \
    -DCMSISCORE="$REPO/firmware/extern/CMSIS_6/CMSIS/Core" \
    "${CMAKE_TC_ARGS[@]}" >/dev/null
fi
echo "▶ [FW.4] cross build logmel_m4.elf…"
cmake --build "$BUILD" --target logmel_m4

if [ -z "$QEMU" ]; then
  echo "✅ [FW.4] logmel_m4.elf зібрано (QEMU-ногу доведе CI)"
  exit 0
fi

echo "▶ [FW.4] qemu-system-arm mps2-an386…"
timeout 120 "$QEMU" -M mps2-an386 -nographic -semihosting \
  -kernel "$BUILD/logmel_m4.elf" < /dev/null | tr -d '\r' > "$OUT/logmel_m4.txt"

grep "LOGMEL-M4" "$OUT/logmel_m4.txt" || true
if ! grep -q "LOGMEL-M4-COMPLETE PASS" "$OUT/logmel_m4.txt"; then
  echo "❌ [FW.4] M4-прогін без PASS — golden-розбіжність або стек поза бюджетом:"
  tail -10 "$OUT/logmel_m4.txt"
  exit 1
fi
echo "✅ [FW.4] M4 CMSIS-шлях ≡ goldens + стек у бюджеті (mps2-an386)"
