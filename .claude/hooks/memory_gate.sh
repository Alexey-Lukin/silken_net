#!/usr/bin/env bash
# Growth gate for the persistent memory corpus.
#
# The corpus lives OUTSIDE the git repo: no `git revert`, no CI that can see it.
# The only enforcement point left is the moment of writing — and that is exactly
# where every previous rule failed, because its carrier stood somewhere else
# (a skill that fires on "clean up", a prompt read during housekeeping).
#
# Three stances, one engine:
#   (stdin JSON)  PostToolUse Edit|Write — silent unless this write makes it worse
#   --audit                              — full battery, exit code is the verdict
#   --genre                              — chronicle detector alone (housekeeping step 1)
set -uo pipefail

MEM_DIR="${MEMORY_GATE_DIR:-/Users/oleksiilukin/.claude/projects/-Users-oleksiilukin-silken-net/memory}"
IDX="$MEM_DIR/MEMORY.md"

# --- Curated thresholds. Bumping one is a deliberate, git-visible decision. ---
# Ratchet, not an absolute cap: the index is already past the 24 kB working cap,
# so an absolute threshold would fire on every write and get muted within a day.
# "No worse than it already is" gives monotone downward pressure and zero noise.
IDX_BASELINE=24814
FILE_CAP=40960          # rule-file ceiling
FILE_WARN=36000        # set just under the known relapse file: it regrew 35->53 kB in 18h
GENRE_MIN=4             # dated blocks, summed across all three costumes

# Dated-chronicle detector. The header-only version was blind to two live
# mutations — dash-lead and bold-lead — which is how two files reached 7-8 dated
# blocks while reading as clean. A fourth costume gets patched HERE, in one
# place, and is live on the very next write: there is no separate "carry the
# lesson into the gate" step left to forget.
genre_count() {
  local f=$1 h l b
  h=$(grep -cE '^#{1,3} .*20[0-9]{2}-[0-9]{2}' "$f")
  l=$(grep -cE '^[-*] .*20[0-9]{2}-[0-9]{2}-[0-9]{2}' "$f")
  b=$(grep -cE '^\*\*[^*]*20[0-9]{2}-[0-9]{2}' "$f")
  printf '%d %d/%d/%d' "$((h + l + b))" "$h" "$l" "$b"
}

# Journals are exempt by design. append=O(1) always beats consolidate=O(n) at
# the end of a session, so the cheap move needs a legal home instead of a fifth
# losing fight against it.
check_file() {
  local fp=$1 f sz g sum shape
  f=$(basename "$fp")
  [ "$f" = "MEMORY.md" ] && return 0
  case $f in log_*) return 0 ;; esac
  [ -f "$fp" ] || return 0
  sz=$(wc -c <"$fp" | tr -d ' ')
  g=$(genre_count "$fp"); sum=${g%% *}; shape=${g##* }
  if [ "$sz" -ge "$FILE_CAP" ]; then
    echo "CAP   $f = ${sz}B over ${FILE_CAP} — the rule stays, its instances move to log_*"
  elif [ "$sz" -ge "$FILE_WARN" ]; then
    echo "WARN  $f = ${sz}B (ceiling ${FILE_CAP})"
  fi
  [ "$sum" -ge "$GENRE_MIN" ] &&
    echo "GENRE $f carries $sum dated blocks (h/l/b = $shape) — chronicle inside a rule file"
  return 0
}

index_check() {
  local sz n
  sz=$(wc -c <"$IDX" | tr -d ' ')
  n=$(grep -cE '^[[:space:]]*- .*\]\([a-z0-9_]+\.md\)' "$IDX")
  if [ "$sz" -gt "$IDX_BASELINE" ]; then
    echo "INDEX MEMORY.md = ${sz}B, past its ${IDX_BASELINE}B ratchet (+$((sz - IDX_BASELINE)), ${n} entries)"
    echo "      a new entry earns its line only by displacing one; detail belongs in the file"
  elif [ "$sz" -lt $((IDX_BASELINE - 400)) ]; then
    echo "INDEX MEMORY.md = ${sz}B, below the ${IDX_BASELINE}B ratchet — lower IDX_BASELINE here to lock the gain in"
  fi
  return 0
}

integrity_check() {
  local fn f l
  for fn in $(grep -oE '\]\([a-z0-9_]+\.md\)' "$IDX" | tr -d ']()' | sort -u); do
    [ -f "$MEM_DIR/$fn" ] || echo "BROKEN  index points at a missing $fn"
  done
  for f in "$MEM_DIR"/*.md; do
    fn=$(basename "$f"); [ "$fn" = "MEMORY.md" ] && continue
    grep -q "($fn)" "$IDX" || echo "ORPHAN  $fn is in no index row"
    { grep -q '^name:' "$f" && grep -q 'type:' "$f"; } || echo "FORMAT  $fn lacks name/type frontmatter"
  done
  # Character class keeps `-` and A-Z on purpose: the dash-form slug is exactly
  # the broken-link shape this check exists for, and macOS resolves case-only
  # mismatches that Linux would not — so both are tested.
  for l in $(grep -rhoE '\[\[[a-zA-Z0-9_-]+\]\]' "$MEM_DIR"/*.md | tr -d '[]' | sort -u); do
    # shellcheck disable=SC2010  # the ls|grep IS the test: -qix asks "does any
    # spelling of this name exist", which is precisely what [ -f ] cannot answer
    # on a case-insensitive filesystem. A glob would silently agree with macOS.
    ls "$MEM_DIR" | grep -qix "$l.md" || { echo "DANGLING [[$l]] resolves to nothing"; continue; }
    [ -f "$MEM_DIR/$l.md" ] || echo "CASE    [[$l]] only resolves on a case-insensitive filesystem"
  done
  return 0
}

case "${1:-}" in
  --audit)
    out=$( { index_check; integrity_check
             for f in "$MEM_DIR"/*.md; do check_file "$f"; done; } )
    printf '%s\n' "${out:-OK — index within ratchet, corpus intact, no chronicle in a rule file}"
    [ -z "$out" ]
    ;;
  --genre)
    for f in "$MEM_DIR"/*.md; do
      g=$(genre_count "$f"); sum=${g%% *}
      [ "$sum" -ge "$GENRE_MIN" ] && printf '%3d  %-46s %s\n' "$sum" "$(basename "$f")" "${g##* }"
    done | sort -rn
    ;;
  *)
    input=$(cat)
    fp=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
    case "$fp" in "$MEM_DIR"/*.md) ;; *) exit 0 ;; esac
    msgs=$( { index_check
              check_file "$fp"
              # A brand-new file is where the registry grows. Nothing reads at
              # this moment except the tool call itself, so this is the only
              # place the question "does this fact already have a home?" can be
              # put while it still matters.
              if [ "$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)" = "Write" ] &&
                 [ "$(basename "$fp")" != "MEMORY.md" ] &&
                 ! grep -q "($(basename "$fp"))" "$IDX"; then
                echo "NEW   $(basename "$fp") is not in the index — route it (own row only if it opens a NEW surface;"
                echo "      otherwise inline it under a hub row) and give it at least one inbound [[string]]"
              fi; } )
    [ -z "$msgs" ] && exit 0
    jq -n --arg ctx "[memory-gate]
$msgs" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$ctx}}'
    ;;
esac
