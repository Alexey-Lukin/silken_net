#!/usr/bin/env bash
# compact_lock.sh — after a compaction, the first repo edit stops ONCE until a skill
# file is read [DOC-T.122].
#
# Measured 2026-10-17 over 31 transcripts: compaction hands the invoked skills back
# cut at ~19.9k CHARACTERS of body — the same point in every domain — so a long skill
# loses its tail (the Gotchas of memory-maintenance and ssot-maintenance, the
# Guard-craft pointer, in-silico's When Modifying, legal-business's gate traps) and
# every companion file is out of context. Each skill's DESCRIPTION names its
# companions, but the skill listing is NOT re-injected after compaction (documented,
# verified 2026-10-17, DOC-T.123), so after the cut only the re-attached heads of
# already-invoked skills name them — and 11 of 13 repo edits after a compaction were
# made without reading one. A pointer the reader may not even have is no carrier;
# this is a LOCK, one file, three stances:
#   --arm      SessionStart, matcher `compact`: arm this session — and reset the memory
#              gate's once-per-session WRITE-TIME marker, whose line compaction dropped
#   --release  PostToolUse Read of any `.claude/skills/*/*.md`: disarm
#   (none)     PreToolUse Edit|Write of a file inside this repo while armed: DENY once,
#              and record that it fired, so the retry passes
# No transcript parsing and no per-domain map: any skill file counts — the lock buys
# one re-orientation, not a verdict on which skill the edit needed.
# ⚠️ Ceilings, named: a skill read through Bash (`sed -n`, `cat`) does not disarm it
# (the one stop still comes, and its reason says Read); files outside the repo — the
# memory corpus, the scratchpad — pass untouched, the memory gate guards the first;
# and an edit OF a skill file never meets the lock: Edit requires a Read of its target,
# and that Read — even a few lines by offset — disarms it (measured live 2026-10-17).
# ⊕ Two more, measured live 2026-10-29: re-invoking a skill through the Skill tool
# hands its whole SKILL.md back yet does not disarm — only a Read does; and an edit
# made through Bash (a script, `sed -i`, `ruby`) never meets the lock at all, because
# the lock stands on Edit|Write — so a session that edits by script after a compaction
# is exactly the case the lock was built for and one it cannot see. And the marker is
# keyed on `session_id`, which a subagent shares with its parent (its transcript carries
# the parent's id; one denial was seen in a subagent that never compacted — what armed
# it was not established): a subagent's edit can spend the parent's one stop, and a
# subagent's Read of a skill file can disarm it.
set -uo pipefail

REPO=$(cd "$(dirname "$0")/../.." && pwd)
marker() { printf '%s/claude-compact-lock-%s' "${TMPDIR:-/tmp}" "$1"; }

# ── --selftest · all three stances, both arms of each ─────────────────────────
# A lock fails in two silent directions: armed forever (every edit denied — loud, so
# it gets switched off) or never armed (reads exactly like «nothing to stop»). Each
# case below pins one of them; fresh session ids and an own TMPDIR keep the markers
# out of the verdicts.
if [[ "${1:-}" == "--selftest" ]]; then
  TMPDIR=$(mktemp -d "${TMPDIR:-/tmp}/compactlock-selftest.XXXXXX"); export TMPDIR
  trap 'rm -rf "$TMPDIR"' EXIT
  self="$0"; fails=0; n=0
  in_repo="$REPO/docs/00_07_Action_Plan_Tracker.md"
  skill="$REPO/.claude/skills/memory-maintenance/traps.md"
  run() {  # run <stance-arg|-> <json> → stdout of the hook
    if [[ "$1" == "-" ]]; then printf '%s' "$2" | bash "$self"; else printf '%s' "$2" | bash "$self" "$1"; fi
  }
  arm()  { run --arm "$(jq -nc --arg s "$1" --arg src "${2:-compact}" '{session_id:$s,source:$src}')"; }
  rd()   { run --release "$(jq -nc --arg s "$1" --arg f "$2" '{session_id:$s,tool_input:{file_path:$f}}')"; }
  ed()   { run - "$(jq -nc --arg s "$1" --arg f "$2" '{session_id:$s,tool_input:{file_path:$f}}')"; }
  c() {  # c <name> <expect deny|silent> <output>
    n=$((n + 1))
    local got=silent
    [[ "$3" == *'"permissionDecision":"deny"'* ]] && got=deny
    if [[ "$got" == "$2" ]]; then printf '  ✓ %-58s %s\n' "$1" "$got"
    else printf '  ✗ %-58s expected %s, got %s\n    out: %s\n' "$1" "$2" "$got" "${3:0:200}"; fails=$((fails + 1)); fi
  }
  s="st-$$-a"; arm "$s"
  c "armed: the first repo edit is DENIED"                deny   "$(ed "$s" "$in_repo")"
  c "armed: the retry passes — the stop is once"          silent "$(ed "$s" "$in_repo")"
  s="st-$$-b"; arm "$s"; rd "$s" "$skill" >/dev/null
  c "a skill companion read disarms it"                   silent "$(ed "$s" "$in_repo")"
  s="st-$$-c"; arm "$s"; rd "$s" "$REPO/.claude/skills/backend/SKILL.md" >/dev/null
  c "a SKILL.md read disarms it too"                      silent "$(ed "$s" "$in_repo")"
  s="st-$$-d"; arm "$s"; rd "$s" "$REPO/docs/00_05_AI_Native_Operating_Model.md" >/dev/null
  c "a NON-skill read leaves it armed"                    deny   "$(ed "$s" "$in_repo")"
  s="st-$$-e"; arm "$s"
  c "an edit OUTSIDE the repo passes"                     silent "$(ed "$s" "$TMPDIR/scratch.md")"
  c "…and the lock stays armed for the next repo edit"    deny   "$(ed "$s" "$in_repo")"
  s="st-$$-f"
  c "never armed: silent"                                 silent "$(ed "$s" "$in_repo")"
  s="st-$$-g"; arm "$s" startup
  c "a NON-compact SessionStart does not arm it"          silent "$(ed "$s" "$in_repo")"
  s="st-$$-h"; arm "$s"
  c "a sibling dir named like the repo is NOT the repo"   silent "$(ed "$s" "${REPO}-other/x.md")"
  # The memory gate's WRITE-TIME marker — reset by a compaction, kept by any other start.
  s="st-$$-i"; : > "$TMPDIR/claude-memory-writetime-$s"; arm "$s" >/dev/null; n=$((n + 1))
  if [[ ! -e "$TMPDIR/claude-memory-writetime-$s" ]]; then printf '  ✓ %-58s %s\n' "a compaction re-arms the memory WRITE-TIME line" "reset"
  else printf '  ✗ %-58s marker survived\n' "a compaction re-arms the memory WRITE-TIME line"; fails=$((fails + 1)); fi
  s="st-$$-j"; : > "$TMPDIR/claude-memory-writetime-$s"; arm "$s" startup >/dev/null; n=$((n + 1))
  if [[ -e "$TMPDIR/claude-memory-writetime-$s" ]]; then printf '  ✓ %-58s %s\n' "…a NON-compact SessionStart leaves it alone" "kept"
  else printf '  ✗ %-58s marker removed\n' "…a NON-compact SessionStart leaves it alone"; fails=$((fails + 1)); fi
  if (( fails > 0 )); then echo "compact_lock --selftest: ${fails}/${n} FAILED"; exit 1; fi
  echo "compact_lock --selftest: OK (${n} cases — arm · release · once-only stop · repo scope)"
  exit 0
fi

input=$(cat)
session=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
[[ -n "$session" ]] || exit 0
m=$(marker "$session")

case "${1:-}" in
  --arm)
    src=$(printf '%s' "$input" | jq -r '.source // "compact"' 2>/dev/null)
    if [[ "$src" == "compact" ]]; then
      printf 'armed\n' > "$m"
      # memory_gate.sh shows its WRITE-TIME rules once per session; compaction drops
      # that line from context while the session's riskiest appends are still ahead,
      # so a compaction re-arms it too (DOC-T.123). Marker name — write_time_once there.
      rm -f "${TMPDIR:-/tmp}/claude-memory-writetime-$session"
    fi
    exit 0
    ;;
  --release)
    fp=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
    [[ "$fp" == "$REPO/.claude/skills/"*/*.md ]] && rm -f "$m"
    exit 0
    ;;
esac

[[ -f "$m" && "$(cat "$m" 2>/dev/null)" == "armed" ]] || exit 0
fp=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[[ "$fp" == "$REPO/"* ]] || exit 0
printf 'fired\n' > "$m"
reason="[compact-lock] Після компакції тіла викликаних скілів повернуто обрізаними (~19.9 тис. символів тіла): хвіст довгого скіла і всі його компаньйони поза контекстом. Перш ніж правити ${fp#"$REPO/"}, прочитай Read-ом компаньйон свого домену (\`ls .claude/skills/<скіл>/\` — опис скіла після компакції не повертається) або сам SKILL.md, тоді повтори правку. Зупинка одна на компакцію (DOC-T.122)."
jq -nc --arg r "$reason" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
exit 0
