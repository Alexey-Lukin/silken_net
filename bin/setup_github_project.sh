#!/usr/bin/env bash
# = =====================================================================
# 🛠 setup_github_project.sh — Projects V2 fields (idempotent)
# = =====================================================================
# Source: docs/00_07_GitHub_Projects_and_IaC_Automation.md §1.2.
# Tracker: docs/00_08_Action_Plan_Tracker.md → OPS.6.
#
# Thin wrapper around `bundle exec rake github:project_fields`. Field
# schema and idempotency live in lib/github_bootstrap.rb so the same
# logic is reachable from Ruby specs.
#
# Env vars:
#   GH_OWNER          — GitHub user/org (default Alexey-Lukin)
#   GH_PROJECT_NUMBER — Project V2 number (default 1)
# = =====================================================================
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v gh >/dev/null 2>&1; then
  echo "❌ \`gh\` CLI is required. Install: https://cli.github.com" >&2
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "❌ \`gh\` is not authenticated. Run \`gh auth login --scopes project,repo\`." >&2
  exit 1
fi

exec bundle exec rake github:project_fields
