#!/usr/bin/env bash
# = =====================================================================
# 🛠 bootstrap_github.sh — full IaC bootstrap for the silken_net repo
# = =====================================================================
# Source: docs/00_05_GitHub_Projects_and_IaC_Automation.md §6.
# Tracker: docs/00_07_Action_Plan_Tracker.md → OPS.6.
#
# Orchestrates the four steps documented in §6:
#
#   1. Labels — pushed via `git push` (labels_sync.yml workflow syncs
#      `.github/labels.yml` automatically on `main` push). We only warn
#      if the working tree has unpushed `.github/labels.yml` changes.
#   2. Projects V2 fields — bin/setup_github_project.sh (idempotent).
#   3. First cycle milestone — `gh api repos/.../milestones` with the
#      default current quarter or the explicit CYCLE_TITLE.
#   4. Baseline shaping doc — only stubbed when SHAPING_STUB is set.
#
# Env vars:
#   GH_OWNER          — GitHub user/org (default Alexey-Lukin)
#   GH_REPO           — repo slug      (default silken_net)
#   GH_PROJECT_NUMBER — Project V2 number (default 1)
#   CYCLE_TITLE       — override milestone title (default = current quarter)
#   CYCLE_DESCRIPTION — optional milestone description
#   SHAPING_STUB      — if set, create `docs/shaping/${SHAPING_STUB}.md`
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

# 1. Labels — warn on unpushed local edits
if git diff --quiet HEAD -- .github/labels.yml; then
  echo "✓  .github/labels.yml is clean — labels_sync.yml will keep state on next push"
else
  echo "⚠️  .github/labels.yml has uncommitted changes — push to main to sync"
fi

# 2 + 3. Projects V2 fields + cycle milestone via rake
exec bundle exec rake "github:bootstrap[${CYCLE_TITLE:-}]"
