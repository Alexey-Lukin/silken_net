#!/usr/bin/env bash
#
# firmware/scripts/cppcheck.sh — Static-analysis gate for first-party firmware C.
#
# The "ruff / rubocop for C". cppcheck statically analyses the OWNED firmware
# (soldier + queen + common + sim) — NOT the vendored extern/ or .toolchain/ trees —
# and fails the build on any real defect: null-deref, buffer overrun, uninit
# read, sign/integer surprise, dead condition. One entry point for CI and for
# local runs (DRY), mirroring firmware/scripts/check_ram_budget.sh and the
# python_lint / lint jobs in .github/workflows/ci.yml.
#
# Usage:
#   firmware/scripts/cppcheck.sh            # gating profile (what CI runs)
#   firmware/scripts/cppcheck.sh --deep     # + --inconclusive (local hunt, FP-prone)
#   firmware/scripts/cppcheck.sh --misra     # + MISRA C:2012 advisory (non-gating)
#   CPPCHECK=/path/to/cppcheck firmware/scripts/cppcheck.sh   # override binary
#
# Local install (no system package needed):
#   conda create -n silken_lint -c conda-forge cppcheck && conda activate silken_lint
# CI installs apt's cppcheck on a pinned ubuntu image (see ci.yml: firmware_lint).
#
# Why these project-wide suppressions are FALSE POSITIVES for THIS codebase
# (documented, not hidden bugs):
#   • missingInclude / missingIncludeSystem — the HAL / CMSIS / mruby headers
#     live only in the ARM build context; cppcheck parses everything else fine
#     without them. Real missing-symbol issues are caught by the ARM cross-build.
#   • staticFunction — the firmware is a single translation unit (main.c) and the
#     host tests compile EXTRACTED logic (firmware/test/*.c never link main.c), so
#     cppcheck sees neither the whole program nor the callers → its "give this
#     internal linkage" advice is architectural noise. Genuinely dead functions
#     are caught by review + the ARM build's -Wunused.
# Everything else is gated. Justified per-site exceptions use inline
# `// cppcheck-suppress <id>` with a reason at the call site (e.g. radio RxDone
# and HAL weak-symbol callbacks whose signatures are ABI-fixed).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

CPPCHECK="${CPPCHECK:-cppcheck}"
PLATFORM="firmware/.cppcheck/stm32wle5.xml"

# sim/ = owned bare-metal C QEMU-ноги (FW.55) — лінтиться нарівні з firmware.
SOURCES=(firmware/soldier firmware/queen firmware/common firmware/sim)
INCLUDES=(-I firmware/common -I firmware/soldier -I firmware/queen -I firmware/sim)

EXTRA=()
RUN_MISRA=0
for arg in "$@"; do
  case "$arg" in
    --deep)  EXTRA+=(--inconclusive) ;;
    --misra) RUN_MISRA=1 ;;
    *) echo "unknown arg: $arg" >&2; exit 2 ;;
  esac
done

ARGS=(
  --enable=warning,performance,portability,style
  --check-level=exhaustive
  --std=c11
  --platform="$PLATFORM"
  --inline-suppr
  --error-exitcode=1
  --quiet
  --suppress=missingInclude
  --suppress=missingIncludeSystem
  --suppress=staticFunction
  --suppress=unmatchedSuppression
  ${EXTRA[@]+"${EXTRA[@]}"}
  "${INCLUDES[@]}"
)

echo "▶ $("$CPPCHECK" --version) — gating soldier + queen + common + sim (Cortex-M4 platform)"
"$CPPCHECK" "${ARGS[@]}" "${SOURCES[@]}"
echo "✅ cppcheck: firmware C clean (no findings at warning/performance/portability/style)"

if [[ "$RUN_MISRA" -eq 1 ]]; then
  echo
  echo "▶ MISRA C:2012 advisory (informational — embedded coding standard, NOT a gate)"
  # The misra.py addon ships with apt's cppcheck (/usr/share/cppcheck/addons/) but
  # NOT with the conda-forge build — degrade gracefully instead of erroring.
  if "$CPPCHECK" --addon=misra --quiet -xc /dev/null >/dev/null 2>&1; then
    "$CPPCHECK" --addon=misra --enable=style --check-level=exhaustive \
      --platform="$PLATFORM" --inline-suppr --quiet \
      --suppress=missingInclude --suppress=missingIncludeSystem --suppress=staticFunction \
      "${INCLUDES[@]}" "${SOURCES[@]}" || true
  else
    echo "ℹ  MISRA addon (misra.py) not bundled with this cppcheck build — skipping."
    echo "   apt's cppcheck ships it; conda-forge does not. CI (apt) can run MISRA."
  fi
fi
