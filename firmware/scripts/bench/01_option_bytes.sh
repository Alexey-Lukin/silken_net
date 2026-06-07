#!/usr/bin/env bash
# 01_option_bytes.sh — [bench] option bytes чеклист SEC.15 + SEC.2.
#
#   IWDG_SW=1   (IWDG software-керований — наш MX_IWDG_Init)
#   IWDG_STOP=0 (SEC.15: ЗАМОРОЗИТИ пса у STOP2 — інакше reset кожні ~26-32 с
#                сну → втрата SRAM/mruby/ota_buffer щоциклу)
#   IWDG_STDBY=0 (узгоджено зі STOP2-політикою)
#   RDP         (SEC.2: R&D = 1; Level 2 — НЕЗВОРОТНІЙ, лише свідомо --rdp 2)
#
#   firmware/scripts/bench/01_option_bytes.sh [--rdp 1] [--execute]
set -euo pipefail

CLI="${STM32_PROGRAMMER_CLI:-STM32_Programmer_CLI}"
RDP=""; EXECUTE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --rdp)     RDP="$2"; shift 2;;
    --execute) EXECUTE=1; shift;;
    *) echo "невідомий аргумент: $1"; exit 2;;
  esac
done

if [ "$RDP" = "2" ]; then
  echo "⚠️  RDP Level 2 НЕЗВОРОТНІЙ (SEC.2 rollout: R&D→Pilot→Mass; спершу жертовний чип)."
  echo "    Підтвердження: набери RDP2 і Enter."
  read -r confirm
  [ "$confirm" = "RDP2" ] || { echo "скасовано"; exit 1; }
fi

cmds=()
cmds+=("$CLI -c port=SWD reset=HWrst")
cmds+=("$CLI -ob IWDG_SW=1 IWDG_STOP=0 IWDG_STDBY=0")
[ -n "$RDP" ] && cmds+=("$CLI -ob RDP=$RDP")
cmds+=("$CLI -ob displ")
cmds+=("$CLI -c port=SWD --quietMode")

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
echo "✅ option bytes застосовано — дамп '-ob displ' вище = артефакт у bench_artifacts/"
