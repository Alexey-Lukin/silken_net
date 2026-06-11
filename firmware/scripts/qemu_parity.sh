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

# soft-float = ABI реального WLE5 (STM32WL — M4 БЕЗ FPU; датащит FPU не знає).
# mps2-an386 у QEMU FPU має, але ми свідомо його не чіпаємо — біти мають
# народжуватись тим самим __aeabi_* шляхом, що й на дереві.
CPU_FLAGS="-mcpu=cortex-m4 -mfloat-abi=soft -mthumb"

# Дзеркало SILKEN_MIN_GEMS (One-Home: firmware/mruby/build_config.rb) — TU,
# що інклудить mruby-хедери, МУСИТЬ бачити ті самі MRB_*-defines, що й ліба
# (інакше layout mrb_state у TU ≠ layout у libmruby.a).
MRB_DEFS="-DMRB_NO_STDIO -DMRB_CONSTRAINED_BASELINE_PROFILE"

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
"$CC_HOST" -std=c11 -O2 -Wall -Wextra $MRB_DEFS "${INC[@]}" -I"$HOST_BUILD/include" \
  -o "$OUT/parity_host" "$REPO/firmware/sim/host_main.c" \
  "$HOST_BUILD/lib/libmruby.a" -lm
"$OUT/parity_host" > "$OUT/host.txt"
grep -q "PARITY-COMPLETE" "$OUT/host.txt" || { echo "❌ host-прогін без маркера"; exit 1; }

# ── ARM-нога: збірка завжди (link-перевірка), запуск — якщо є qemu ──────
echo "▶ [FW.55] arm-none-eabi build…"
"$arm_gcc" $CPU_FLAGS -std=gnu11 -O2 -Wall -Wextra $MRB_DEFS \
  -ffunction-sections -fdata-sections -nostartfiles \
  "${INC[@]}" -I"$ARM_BUILD/include" \
  -T "$REPO/firmware/sim/qemu_m4/mps2_an386.ld" -Wl,--gc-sections \
  -o "$OUT/parity_arm.elf" \
  "$REPO/firmware/sim/qemu_m4/main.c" \
  "$REPO/firmware/sim/qemu_m4/startup.c" \
  "$REPO/firmware/sim/qemu_m4/syscalls.c" \
  "$ARM_BUILD/lib/libmruby.a" -lm

# ── WLE5 bench-нога (RUNBOOK 2.3): збірка ЗАВЖДИ — link-check, щоб
#    кремнієвий runner не гнив до bench-дня; фіт гейтиться нижче. ─────────
echo "▶ [FW.55] wle5-bench build (кремнієва нога, RUNBOOK 2.3)…"
"$arm_gcc" $CPU_FLAGS -std=gnu11 -O2 -Wall -Wextra $MRB_DEFS \
  -ffunction-sections -fdata-sections -nostartfiles \
  "${INC[@]}" -I"$ARM_BUILD/include" \
  -T "$REPO/firmware/sim/wle5_bench/stm32wle5.ld" -Wl,--gc-sections \
  -o "$OUT/parity_wle5.elf" \
  "$REPO/firmware/sim/wle5_bench/main.c" \
  "$REPO/firmware/sim/wle5_bench/startup.c" \
  "$REPO/firmware/sim/wle5_bench/syscalls.c" \
  "$ARM_BUILD/lib/libmruby.a" -lm

# Числа фіту з реального bench-ELF: static RAM → heap-бюджет 64КБ-карти
# (stack-резерв One-Home у stm32wle5.ld; flash-фіт довів би сам лінкер).
arm_size="${arm_gcc%gcc}size"
read -r wle5_text wle5_data wle5_bss <<<"$("$arm_size" "$OUT/parity_wle5.elf" | awk 'NR==2{print $1, $2, $3}')"
stack_reserve="$(sed -n 's/^__stack_reserve__ = \([0-9]*\);.*/\1/p' "$REPO/firmware/sim/wle5_bench/stm32wle5.ld")"
heap_budget=$(( 65536 - stack_reserve - wle5_data - wle5_bss ))
echo "  wle5: flash $(( wle5_text + wle5_data ))/262144 Б, static RAM $(( wle5_data + wle5_bss )) Б, heap-бюджет $heap_budget Б, stack-резерв $stack_reserve Б"

if [ -z "$QEMU" ]; then
  echo "✅ [FW.55] host-голден OK + ARM .elf + wle5-bench .elf зібрано (QEMU-ногу і фіт-гейт доведе CI)"
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

# ── WLE5-фіт: QEMU-числа переносяться на кремній (той самий libmruby/newlib
#    → ідентична послідовність malloc'ів) — «не влазить у 64КБ» ловимо ТУТ. ──
grep '^PARITY-MEM' "$OUT/arm.txt" | sed 's/^/  /' || true
grep '^SBRK' "$OUT/arm.txt" | sed 's/^/  /' | tail -30 || true
heap_high="$(sed -n 's/^PARITY-HEAP high-water=\([0-9]*\)$/\1/p' "$OUT/arm.txt")"
stack_high="$(sed -n 's/^PARITY-STACK high-water=\([0-9]*\)$/\1/p' "$OUT/arm.txt")"
if [ -z "$heap_high" ] || [ -z "$stack_high" ]; then
  echo "❌ [FW.55] фіт-маркери PARITY-HEAP/PARITY-STACK не прийшли з QEMU"
  exit 1
fi
if [ "$heap_high" -gt "$heap_budget" ]; then
  echo "❌ [FW.55] mruby-прогін НЕ ВЛАЗИТЬ у WLE5: heap $heap_high Б > бюджет $heap_budget Б (64КБ SRAM)"
  exit 1
fi
if [ "$stack_high" -gt "$stack_reserve" ]; then
  echo "❌ [FW.55] стек глибший за резерв wle5-карти: $stack_high Б > $stack_reserve Б"
  exit 1
fi
echo "✅ [FW.55] WLE5-фіт: heap $heap_high/$heap_budget Б, stack $stack_high/$stack_reserve Б — кремнієвій нозі є де жити"
