#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# 00_flash.sh — [bench] прошивка .elf/.bin через STM32_Programmer_CLI.
# Той самий бінарник, що у SEC.3 pipeline (шим-інтеграція довела оркестрацію,
# не семантику CLI; тут — фізичний SWD). Без --execute лише друкує план
# (узгоджено з dry-run-філософією factory:flash).
#
#   firmware/scripts/bench/00_flash.sh --elf build/soldier.elf [--execute]
#   firmware/scripts/bench/00_flash.sh --bin fw.bin --addr 0x08000000 --execute
set -euo pipefail

CLI="${STM32_PROGRAMMER_CLI:-STM32_Programmer_CLI}"
ELF=""; BIN=""; ADDR="0x08000000"; EXECUTE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --elf)     ELF="$2"; shift 2;;
    --bin)     BIN="$2"; shift 2;;
    --addr)    ADDR="$2"; shift 2;;
    --execute) EXECUTE=1; shift;;
    *) echo "невідомий аргумент: $1"; exit 2;;
  esac
done

[ -n "$ELF$BIN" ] || { echo "потрібен --elf або --bin"; exit 2; }

# Кожен виклик CLI — окремий процес, тож `-c` несе КОЖЕН рядок: з'єднання
# між процесами не живе, а «disconnect» окремим рядком не існує.
CONNECT="-c port=SWD reset=HWrst"

cmds=()
if [ -n "$ELF" ]; then
  cmds+=("$CLI $CONNECT -w \"$ELF\" -v")
else
  cmds+=("$CLI $CONNECT -w \"$BIN\" $ADDR -v")
fi

if [ "$EXECUTE" != "1" ]; then
  echo "— план (без --execute нічого не виконується) —"
  printf '[plan] %s\n' "${cmds[@]}"
  exit 0
fi

command -v "$CLI" >/dev/null 2>&1 || { echo "❌ $CLI відсутній у PATH"; exit 1; }
for c in "${cmds[@]}"; do
  echo "▶ $c"
  eval "$c"
done
echo "✅ flash + verify завершено"
