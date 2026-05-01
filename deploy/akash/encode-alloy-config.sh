#!/usr/bin/env bash
# =============================================================================
# encode-alloy-config.sh — Base64-encode deploy/akash/config.alloy for SDL
# =============================================================================
#
# Purpose: Generate the value for ALLOY_CONFIG_BASE64 env var in Akash SDL
# (deploy/akash/deploy.yaml → services.alloy.env). The Alloy sidecar decodes
# this at startup: `echo $ALLOY_CONFIG_BASE64 | base64 -d > /etc/alloy/config.alloy`.
#
# Usage:
#   ./deploy/akash/encode-alloy-config.sh                  # prints to stdout
#   ./deploy/akash/encode-alloy-config.sh --check          # only prints sanity report
#   ALLOY_CONFIG=path/to/custom.alloy ./encode-alloy-config.sh
#
# When to use:
#   - **Manual SDL deploy** without Terraform (BLOCKER-3 manual workflow).
#   - When Terraform's `filebase64()` is not invoked (e.g. Akash Console UI).
#
# When NOT to use:
#   - With Terraform: `terraform/akash/main.tf` already calls `filebase64()`
#     during template rendering. Do not paste this script's output into
#     `terraform.tfvars` — the template applies base64 itself.
#
# Why this script (INF.7):
#   `base64` defaults differ across distros (macOS has no `-w`; GNU coreutils
#   wraps at column 76 unless `-w 0` is passed). Wrapped output breaks the
#   `echo $ALLOY_CONFIG_BASE64 | base64 -d` decode path in the Alloy entrypoint
#   (newlines inside the env var are silently truncated by some shells).
#   This script forces a single-line, no-newline encoding and verifies that
#   round-tripping the result produces the original file byte-for-byte.
# =============================================================================

set -euo pipefail

ALLOY_CONFIG="${ALLOY_CONFIG:-$(dirname "$0")/config.alloy}"
CHECK_ONLY=0

for arg in "$@"; do
  case "$arg" in
    --check) CHECK_ONLY=1 ;;
    -h|--help)
      sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      exit 2
      ;;
  esac
done

if [[ ! -f "$ALLOY_CONFIG" ]]; then
  echo "❌ Config file not found: $ALLOY_CONFIG" >&2
  exit 1
fi

# Detect base64 flavor (GNU coreutils vs BSD/macOS)
if base64 --help 2>&1 | grep -q -- '-w'; then
  # GNU: -w 0 disables line wrapping
  ENCODED="$(base64 -w 0 < "$ALLOY_CONFIG")"
else
  # BSD/macOS: no wrapping by default, but tr to be safe
  ENCODED="$(base64 < "$ALLOY_CONFIG" | tr -d '\n')"
fi

# Sanity: encoded string must be a single line, base64 alphabet only
if [[ "$ENCODED" == *$'\n'* ]]; then
  echo "❌ Encoded output contains newlines — would break SDL env decode" >&2
  exit 1
fi
if ! [[ "$ENCODED" =~ ^[A-Za-z0-9+/=]+$ ]]; then
  echo "❌ Encoded output contains non-base64 characters" >&2
  exit 1
fi

# Round-trip verification: decode and compare to source byte-for-byte.
# This catches subtle issues like CRLF line endings or BOM bytes.
DECODED="$(printf '%s' "$ENCODED" | base64 -d)"
if [[ "$DECODED" != "$(cat "$ALLOY_CONFIG")" ]]; then
  echo "❌ Round-trip mismatch — decoded content does not equal source" >&2
  exit 1
fi

if [[ "$CHECK_ONLY" -eq 1 ]]; then
  echo "✅ $ALLOY_CONFIG: $(wc -c < "$ALLOY_CONFIG") bytes → ${#ENCODED} base64 chars (single line, round-trip OK)"
  exit 0
fi

# Print encoded value to stdout (no trailing newline — paste-ready).
printf '%s' "$ENCODED"
