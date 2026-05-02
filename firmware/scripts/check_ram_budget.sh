#!/usr/bin/env bash
# [FW.26] RAM budget verification for firmware ELF artifacts.
#
# Runs `arm-none-eabi-size` on Soldier/Queen ELF if present and asserts that
# `.bss + .data` (static RAM) stays within the budget. STM32WLE5JC has 64 KB
# SRAM; we reserve at minimum 14 KB for runtime stack + heap + tensor arena
# headroom (FW.4 TinyML model + FW.6 Lorenz state + mruby VM + Sidekiq-style
# task buffers), so the static-RAM hard limit is set to 50 000 bytes.
#
# Behavior:
#   - If no ELF is present (FW.4 not yet linked, no ARM toolchain run) → exit 0
#     with informational message. This keeps CI green until the production
#     ELF pipeline lands.
#   - If ELF present and `.bss + .data > BUDGET_BYTES` → exit 1 (CI gate).
#   - Otherwise → emit a one-line report.
#
# Usage:
#   firmware/scripts/check_ram_budget.sh \
#     [path/to/soldier.elf [path/to/queen.elf]]
#
# Defaults search firmware/{soldier,queen}/build/*.elf relative to repo root.
set -euo pipefail

BUDGET_BYTES="${BUDGET_BYTES:-50000}"
SIZE_TOOL="${SIZE_TOOL:-arm-none-eabi-size}"

if ! command -v "${SIZE_TOOL}" >/dev/null 2>&1; then
    echo "[FW.26] '${SIZE_TOOL}' not on PATH — skipping (install gcc-arm-none-eabi to enable)."
    exit 0
fi

# Collect candidate ELF paths
candidates=()
if [[ $# -gt 0 ]]; then
    candidates=("$@")
else
    while IFS= read -r -d '' f; do
        candidates+=("$f")
    done < <(find firmware/soldier/build firmware/queen/build -maxdepth 2 -name '*.elf' -print0 2>/dev/null || true)
fi

if [[ ${#candidates[@]} -eq 0 ]]; then
    echo "[FW.26] No ELF artifacts found — skipping RAM budget check."
    echo "[FW.26] (Cross-compile pipeline not yet wired; gate will activate after FW.4)."
    exit 0
fi

fail=0
for elf in "${candidates[@]}"; do
    if [[ ! -f "$elf" ]]; then
        echo "[FW.26] ${elf}: not found, skipping"
        continue
    fi

    # Berkeley format columns: text data bss dec hex filename
    line=$("${SIZE_TOOL}" -B "$elf" | awk 'NR==2 {print $1" "$2" "$3}')
    text=$(awk '{print $1}' <<<"$line")
    data=$(awk '{print $2}' <<<"$line")
    bss=$(awk '{print $3}' <<<"$line")
    static_ram=$((data + bss))

    printf '[FW.26] %s text=%d data=%d bss=%d static_ram=%d (budget=%d)\n' \
        "$elf" "$text" "$data" "$bss" "$static_ram" "$BUDGET_BYTES"

    if [[ $static_ram -gt $BUDGET_BYTES ]]; then
        echo "[FW.26] FAIL: static RAM (${static_ram} B) exceeds budget (${BUDGET_BYTES} B) for ${elf}"
        fail=1
    fi
done

exit "$fail"
