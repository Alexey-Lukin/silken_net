#!/usr/bin/env bash
# PreToolUse hook on `Bash` — the shell-verification rules, at the moment of the call.
#
# These rules were written in memory and relapsed ≥9 documented times, because a
# rule about how to READ a command's output has to arrive while the command is
# being typed, and nowhere else. Everything here is measured over 17,206 real
# Bash calls from 210 sessions; the numbers in each block are that measurement.
#
# DESIGN STANCE — deliberately biased toward FALSE NEGATIVES. A hook that nags is
# a hook that gets bypassed, and then the rule has no carrier at all, which is
# strictly worse than today. So every detector is anchored narrowly and every
# known-legitimate idiom is excluded, even at the cost of missing real instances.
#
# Two rules were MEASURED AND DROPPED, and the measurement is the point:
#   · zsh word-splitting — 9-15 candidates in a month, and whether a bare `$var`
#     is a bug depends on the variable's runtime CONTENT, which no regex sees.
#     Any pattern here is a coin-flip that trains the reader to ignore the hook.
#   · `cd` persistence — real, but the harness ALREADY carries it: 95.7% of calls
#     ending outside the repo print "Shell cwd was reset to …". A hook here would
#     duplicate a live carrier and add ~1,272 firings of pure noise.
set -uo pipefail

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
session=$(printf '%s' "$input" | jq -r '.session_id // "nosession"' 2>/dev/null)
[[ -n "$cmd" ]] || exit 0

# ── BLOCK · backtick inside `git commit -m "…"` ──────────────────────────────
# 2 calls in 17,206 — and the damage is in this repo's history permanently: a
# commit message whose sentence lost its subject because `…` ran as a command
# substitution, returned empty, and vanished silently. Nothing fails, nothing
# warns, and git history cannot be rewritten after a push.
# The dominant idioms are already safe and stay silent: `-F -` (587 uses),
# `-m "$(cat <<'QUOTED')"` (110), `$(printf …)`, and escaped \`.
if printf '%s' "$cmd" | grep -qE 'git[[:space:]]+commit[^|;]*-m[[:space:]]+"[^"]*[^\\]`'; then
  if ! printf '%s' "$cmd" | grep -qE -- '-m[[:space:]]+"\$\('; then
    jq -nc --arg r 'Backtick inside git commit -m "…": the shell will RUN it as a command substitution and silently drop the text — it does not fail, and after a push the message cannot be fixed. This repo already carries one such sentence, meaningless forever. Use `git commit -F -` with a heredoc instead.' \
      '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
    exit 0
  fi
fi

# ── WARN · once per session per class ────────────────────────────────────────
# The marker idiom is borrowed from ssot_guard_hint.sh for the reason stated
# there: a noisy advisory is a disabled gate. It takes rule A from 1,564 firings
# a month to ≤158, and rule B from 393 to ≤133.
warn() {
  local class=$1 text=$2 marker
  marker="${TMPDIR:-/tmp}/claude-bashguard-${session}-${class}"
  [[ -f "$marker" ]] && return 0
  : > "$marker"
  jq -nc --arg ctx "$text" '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$ctx}}'
  exit 0
}

# Already reading the pipeline's real status → silent. 222 calls do this, and
# three of the first five false positives measured were exactly this case.
if ! printf '%s' "$cmd" | grep -qE 'PIPESTATUS|pipefail'; then

  # ── A · a GATE truncated into head/tail (9.09% naive→scoped, ~97% precise) ──
  # The discriminator is the PRODUCER, not the pipe: of 11,712 head/tail
  # pipelines, 5,876 are grep and 283 ls — all legitimate. So the producer must
  # be an actual verdict-emitting gate AND stand at the START of its statement;
  # that anchor is what kills the measured false-positive class, where the word
  # matched a FILENAME (`grep -n … config/brakeman.ignore | head`).
  # Report generators are deliberately absent from this list: stan_audit.rb and
  # mem_find.rb have no `exit 1` path at all, so slicing them is querying, not
  # truncating a verdict.
  gate='(bin/rspec|bundle exec rspec|bin/rubocop|bundle exec rubocop|bin/brakeman|bin/bundler-audit|bin/ci|make -C firmware/test|forge (test|build|coverage)|ruff check|pytest|bin/rails (docs:|tracker:|gaia:|zeitwerk:|spec)|rake (docs:|tracker:))'
  if printf '%s' "$cmd" | grep -qE "(^|[;&]|&&|\|\||^[[:space:]]*)[[:space:]]*(env [^|;]* )?${gate}" &&
     printf '%s' "$cmd" | grep -qE '\|[[:space:]]*(head|tail)([[:space:]]|$)' &&
     ! printf '%s' "$cmd" | grep -qE 'tail[[:space:]]+-[fF]|--dry-run|--help|--version|--tasks|--list' ; then
    warn gate-truncated '[bash-guard] A gate is piped into head/tail. Truncating hides the verdict, and "0 failures" in the visible tail is not one — the run can fail after the lines you kept. Pin the object and grep the step'"'"'s own output, or keep the exit code with PIPESTATUS. (Fires once per session.)'
  fi

  # ── B · `$?` read after a pipe or a background start (2.28%, 15/15 precise) ──
  # `$?` returns the status of the LAST element, and head/tail/`&` are always 0 —
  # so this reads success unconditionally. Measured instances include a failed
  # `git push` read as success and a mutation-verify that could not fail. A
  # terminal bare `grep` is EXCLUDED: reading grep's status is a deliberate,
  # documented idiom here ("1 = zero hits"), not a mistake.
  # ⚠️ The `&` half must be a real BACKGROUND operator, not a redirect. The first
  # live firing of this hook was a false positive on `cmd > out 2>&1; echo $?` —
  # where `$?` is exactly right, because a redirect does not change whose status
  # it is. So `&` counts only when it TERMINATES the statement (`… & ; echo`),
  # never when preceded by `>`/`<`/another `&`. Caught by shipping it, which is
  # also the argument for shipping: the measurement missed this class entirely.
  if { printf '%s' "$cmd" | grep -qE '[^|]\|[^|][^;]*;[[:space:]]*echo[^;]*\$\?' ||
       printf '%s' "$cmd" | grep -qE '[^>&<]&[[:space:]]*;[[:space:]]*echo[^;]*\$\?' ; } &&
     ! printf '%s' "$cmd" | grep -qE '\|[[:space:]]*grep[^|;]*;[[:space:]]*echo[^;]*\$\?' ; then
    warn exit-after-pipe '[bash-guard] `$?` after a pipe or a background start reports the LAST element, and head/tail/`&` always exit 0 — so this reads success no matter what happened upstream. Use ${PIPESTATUS[0]}, or run the command unpiped and echo $? on its own line. (Fires once per session.)'
  fi
fi

exit 0
