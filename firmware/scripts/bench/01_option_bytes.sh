#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# 01_option_bytes.sh — [bench] option bytes чеклист SEC.15 + SEC.2.
#
#   IWDG_SW=1   (IWDG software-керований — наш MX_IWDG_Init)
#   IWDG_STOP=0 (SEC.15: ЗАМОРОЗИТИ пса у STOP2 — інакше reset кожні ~26-32 с
#                сну → втрата SRAM/mruby/ota_buffer щоциклу)
#   IWDG_STDBY=0 (узгоджено зі STOP2-політикою)
#   RDP         (SEC.2: R&D = 1; Level 2 — НЕЗВОРОТНІЙ, лише свідомо --rdp 2)
#               --rdp бере НОМЕР рівня, а CLI — СИРИЙ байт поля (UM2237: «-ob
#               OptByte=<value>»), тож 0/1/2 → 0xAA/0xBB/0xCC (OB_RDP_LEVEL_* у
#               stm32wlxx_hal_flash.h; будь-який інший байт кремній читає як L1).
#               Дзеркало мапи — FactoryFlashing::CommandBuilder::RDP_OPTION_BYTE.
#
#   firmware/scripts/bench/01_option_bytes.sh [--rdp 0|1|2] [--execute]
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

case "$RDP" in
  "") RDP_BYTE="";;
  0)  RDP_BYTE="0xAA"; echo "⚠️  L1 → L0 = регресія з масовим стиранням Flash (ключі теж).";;
  1)  RDP_BYTE="0xBB";;
  2)  RDP_BYTE="0xCC";;
  *)  echo "--rdp: 0 | 1 | 2 (номер рівня), отримано: $RDP"; exit 2;;
esac

if [ "$RDP" = "2" ]; then
  echo "⚠️  RDP Level 2 НЕЗВОРОТНІЙ (SEC.2 rollout: R&D→Pilot→Mass; спершу жертовний чип)."
  echo "    Підтвердження: набери RDP2 і Enter."
  read -r confirm
  [ "$confirm" = "RDP2" ] || { echo "скасовано"; exit 1; }
fi

cmds=()
cmds+=("$CLI -c port=SWD reset=HWrst")
cmds+=("$CLI -ob IWDG_SW=1 IWDG_STOP=0 IWDG_STDBY=0")
[ -n "$RDP_BYTE" ] && cmds+=("$CLI -ob RDP=$RDP_BYTE")
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
