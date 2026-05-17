#!/usr/bin/env bash
# PostToolUse hook — doc-drift early warning.
# Triggered after Edit/Write on any file under app/.
# Extracts changed Ruby symbols (def/class/module) via git diff HEAD,
# greps them in docs/, and returns a list as additionalContext so Claude
# knows which canonical documents may need updating.
set -uo pipefail

input=$(cat)
file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

# Only process files under app/
[[ "$file_path" == *"/app/"* ]] || exit 0

# Resolve repo root from the edited file's directory
repo_root=$(git -C "$(dirname "$file_path")" rev-parse --show-toplevel 2>/dev/null) || exit 0
rel_path="${file_path#$repo_root/}"

# Extract new (+) symbol names from diff (HEAD to working tree).
# Captures: def method, def self.method, class Foo, module Bar
symbols=$(
  git -C "$repo_root" diff HEAD -- "$rel_path" 2>/dev/null |
  grep -E '^\+[^+]' |
  grep -oE 'def (self\.)?[a-zA-Z_][a-zA-Z0-9_!?]*|class [A-Z][a-zA-Z0-9_:]*|module [A-Z][a-zA-Z0-9_:]*' |
  awk '{print $NF}' |
  sed 's/.*\.//' |
  sort -u
)

[[ -z "$symbols" ]] && exit 0

# For each symbol grep docs/ and collect unique files
doc_list=""
while IFS= read -r sym; do
  [[ -z "$sym" ]] && continue
  hits=$(grep -rl "$sym" "$repo_root/docs/" 2>/dev/null |
         sed "s|$repo_root/||" |
         sort |
         tr '\n' ', ' |
         sed 's/,$//')
  [[ -n "$hits" ]] && doc_list+="  ${sym} → ${hits}\n"
done <<< "$symbols"

[[ -z "$doc_list" ]] && exit 0

msg="[Doc-drift] Changed symbols in ${file_path##*/} appear in docs — check for drift:\n${doc_list}"

jq -n --arg ctx "$(printf '%b' "$msg")" \
  '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$ctx}}'
