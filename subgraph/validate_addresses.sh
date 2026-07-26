#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-or-later
# Validates that subgraph.yaml does not contain placeholder zero addresses.
# Run before `graph deploy` to prevent indexing from genesis block with no events.
#
# Usage: ./subgraph/validate_addresses.sh
# CI: add as a step before `graph deploy` in .github/workflows/

set -e

SUBGRAPH_FILE="$(dirname "$0")/subgraph.yaml"
ZERO_ADDR="0x0000000000000000000000000000000000000000"

if grep -q "address: \"${ZERO_ADDR}\"" "$SUBGRAPH_FILE"; then
  echo "ERROR: subgraph.yaml contains placeholder zero addresses." >&2
  echo "Deploy SilkenCarbonCoin and SilkenForestCoin contracts first, then:" >&2
  echo "  1. Update 'address' fields in subgraph/subgraph.yaml" >&2
  echo "  2. Set 'startBlock' to the deployment block number" >&2
  echo "  3. Run: graph codegen && graph build && graph deploy" >&2
  exit 1
fi

echo "subgraph.yaml address validation passed."
exit 0
