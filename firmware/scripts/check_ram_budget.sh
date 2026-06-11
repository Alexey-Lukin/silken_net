#!/usr/bin/env bash
# [FW.26] RAM budget verification — static RAM (.data+.bss) проти леджера.
#
# Леджер Солдата (виміряно 2026-06-11, не «оцінки»):
#   SRAM 65536
#   − mruby heap  38392  (QEMU sbrk-плато FW.55, nano, конservative — із зонд-
#                         оверхедом ~+4-5КБ; чистий ~34К; справжній live ~27К)
#   − stack       12288  (резерв wle5-карти, FW.55 фіт-гейт; виміряний слід 2.9К)
#   = 14856 Б на ВСЮ статику Солдата (TU .bss+.data + libc/HAL/common)
#     → з них tensor arena (FW.4, ляже у .bss) ≈ 7-15КБ СТЕЛЯ залежно від
#     mruby-капу — Path B «~16КБ» НЕ влазить без INT8/prune. Канон: 03_03 §6.
#
# Режими:
#   1) --hal-objects <cmake-build-dir>  — РЕАЛЬНІ ARM-статики обох main.c
#      (compile-lane FW.46 .obj; працює ВЖЕ, до повного .elf). Per-TU бюджети:
#      Soldier 8192 (зараз ~5.7К; прихід arena зірве гейт → свідома ревізія),
#      Queen  20480 (зараз ~18.4К: CIFO + OTA 8К + модемні буфери).
#   2) ELF-режим (після HAL-link): бюджет per-target — soldier 14800 (леджер),
#      queen 40960 (без mruby/arena; стек+heap модема).
#   Нема інструмента/артефактів → чесний skip (exit 0), як інші bench-гейти.
#
# Usage:
#   firmware/scripts/check_ram_budget.sh --hal-objects firmware/build
#   firmware/scripts/check_ram_budget.sh [path/to/soldier.elf [queen.elf]]
set -euo pipefail

SIZE_TOOL="${SIZE_TOOL:-arm-none-eabi-size}"
SOLDIER_TU_BUDGET="${SOLDIER_TU_BUDGET:-8192}"
QUEEN_TU_BUDGET="${QUEEN_TU_BUDGET:-20480}"
SOLDIER_ELF_BUDGET="${SOLDIER_ELF_BUDGET:-14800}"
QUEEN_ELF_BUDGET="${QUEEN_ELF_BUDGET:-40960}"

if ! command -v "${SIZE_TOOL}" >/dev/null 2>&1; then
    echo "[FW.26] '${SIZE_TOOL}' not on PATH — skipping (install gcc-arm-none-eabi to enable)."
    exit 0
fi

static_ram_of() { # file → "<text> <data> <bss>"
    "${SIZE_TOOL}" -B "$1" | awk 'NR==2 {print $1" "$2" "$3}'
}

check_one() { # file budget label → fail-flag via global
    local f="$1" budget="$2" label="$3"
    local line text data bss static_ram
    line=$(static_ram_of "$f")
    text=$(awk '{print $1}' <<<"$line")
    data=$(awk '{print $2}' <<<"$line")
    bss=$(awk '{print $3}' <<<"$line")
    static_ram=$((data + bss))
    printf '[FW.26] %s text=%d data=%d bss=%d static_ram=%d (budget=%d)\n' \
        "$label" "$text" "$data" "$bss" "$static_ram" "$budget"
    if [[ $static_ram -gt $budget ]]; then
        echo "[FW.26] FAIL: static RAM (${static_ram} B) exceeds budget (${budget} B) for ${label}"
        fail=1
    fi
}

fail=0

if [[ "${1:-}" == "--hal-objects" ]]; then
    build_dir="${2:?--hal-objects потребує cmake-build-dir}"
    s_obj="$build_dir/CMakeFiles/hal_check.dir/hal_glue/soldier_hal_check.c.obj"
    q_obj="$build_dir/CMakeFiles/hal_check.dir/hal_glue/queen_hal_check.c.obj"
    if [[ ! -f "$s_obj" || ! -f "$q_obj" ]]; then
        echo "[FW.26] hal_check .obj не знайдено у ${build_dir} — спершу збудуй таргет hal_check."
        exit 1
    fi
    check_one "$s_obj" "$SOLDIER_TU_BUDGET" "soldier(main.c TU)"
    check_one "$q_obj" "$QUEEN_TU_BUDGET" "queen(main.c TU)"
    if [[ $fail -eq 0 ]]; then
        echo "[FW.26] ✅ ARM static-RAM у леджері (стеля tensor arena ≈ 7-15КБ — 03_03 §6)"
    fi
    exit "$fail"
fi

# ── ELF-режим (після HAL-link) ──────────────────────────────────────────
candidates=()
if [[ $# -gt 0 ]]; then
    candidates=("$@")
else
    while IFS= read -r -d '' f; do
        candidates+=("$f")
    done < <(find firmware/soldier/build firmware/queen/build -maxdepth 2 -name '*.elf' -print0 2>/dev/null || true)
fi

if [[ ${#candidates[@]} -eq 0 ]]; then
    echo "[FW.26] No ELF artifacts found — skipping (повний .elf прийде з HAL-фазою; до того гейтить --hal-objects)."
    exit 0
fi

for elf in "${candidates[@]}"; do
    if [[ ! -f "$elf" ]]; then
        echo "[FW.26] ${elf}: not found, skipping"
        continue
    fi
    budget="$SOLDIER_ELF_BUDGET"
    case "$elf" in *queen*) budget="$QUEEN_ELF_BUDGET";; esac
    check_one "$elf" "$budget" "$elf"
done

exit "$fail"
