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
# One rule was MEASURED AND DROPPED and stays dropped:
#   · `cd` persistence — real, but the harness ALREADY carries it: 95.7% of calls
#     ending outside the repo print "Shell cwd was reset to …". A hook here would
#     duplicate a live carrier and add ~1,272 firings of pure noise.
#
# A second was dropped and then OVERTURNED, and the reversal is the more useful
# record than either verdict. The refusal read: "whether a bare `$var` is a bug
# depends on the variable's runtime CONTENT, which no regex sees." That is true
# of the BROAD form and false of a narrow one — `for x in $list` and
# `set -- $pair` carry the defect in their SYNTAX, because zsh does not split an
# unquoted scalar at all, so the multi-wordness never has to be guessed. Both
# halves re-measured 2026-08-08 over 17,524 calls / 32.3 days: the broad anchor
# yields ~975/month at ~2-3% precision (rightly refused, do not reopen it), the
# narrow one 18 findings — ~17/month — every one confirmed against the RECORDED
# OUTPUT of that same call rather than by reading its code. Rule C is that
# anchor. It is not a regex, and the reason why lives in zsh_split_scan.rb.
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
if ! printf '%s' "$cmd" | grep -qE 'PIPESTATUS|pipestatus|pipefail'; then

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
    warn gate-truncated '[bash-guard] A gate is piped into head/tail. Truncating hides the verdict, and "0 failures" in the visible tail is not one — the run can fail after the lines you kept. Pin the object and grep the step'"'"'s own output, or keep the exit code with $pipestatus[1] (zsh; PIPESTATUS is a bash-ism and expands to EMPTY here). (Fires once per session.)'
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
  # 🔴 KNOWN GAP, measured 2026-08-11 and deliberately NOT patched here. That
  # exclusion is right only in the FOREGROUND. Launched with the tool's
  # `run_in_background`, the very same `cmd > log 2>&1; echo "EXIT=$?"` makes the
  # HARNESS report the chain's status — i.e. the `echo`'s 0 — so its completion
  # notice said "exit code 0" about an rspec run that had died on the coverage
  # floor with 2. One text, two contexts, opposite verdicts; this detector keys
  # on text alone, while the discriminator (`.tool_input.run_in_background`) sits
  # in the JSON already parsed above. Patching it unmeasured would violate this
  # file's own stance (every block carries its corpus count), so the honest form
  # is: measure that flag's real firing rate first, then add a narrow rule.
  # Until then the carrier has a hole — the reader is the check. Rule-home for
  # the class: memory `feedback_verify_gate_exit_code`, fourth family (a).
  if { printf '%s' "$cmd" | grep -qE '[^|]\|[^|][^;]*;[[:space:]]*echo[^;]*\$\?' ||
       printf '%s' "$cmd" | grep -qE '[^>&<]&[[:space:]]*;[[:space:]]*echo[^;]*\$\?' ; } &&
     ! printf '%s' "$cmd" | grep -qE '\|[[:space:]]*grep[^|;]*;[[:space:]]*echo[^;]*\$\?' ; then
    warn exit-after-pipe '[bash-guard] `$?` after a pipe or a background start reports the LAST element, and head/tail/`&` always exit 0 — so this reads success no matter what happened upstream. Use $pipestatus[1] — this shell is zsh, where the array is lowercase and 1-INDEXED; ${PIPESTATUS[0]} expands to an empty string, so a check built on it silently compares against nothing. Or run the command unpiped and echo $? on its own line. (Fires once per session.)'
  fi
fi

# ── C · BLOCK · a loop over an unsplit scalar (18 in 17,524, 18/18 confirmed) ──
# This is the one place the file's false-negative bias is overridden on purpose,
# because the failure is a FALSE GREEN and it is silent by construction. Of the
# 18 measured instances: one printed "порожньо = добре" immediately before `rm`
# of seven memory files, one printed EXIT=0 for six gates immediately before
# `git push`, and one turned a loop that never ran into a plausible WRONG
# CONCLUSION ("no probe output — at_exit skipped"). None of them looked broken.
# The prefilter is a strict superset of the scanner's own anchors and keeps ruby
# off 88% of calls (2,115 of 17,524 reach it, ~33 ms each).
if printf '%s' "$cmd" | grep -qE '\bfor[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]+in\b|set[[:space:]]+--'; then
  scan="$(dirname "$0")/zsh_split_scan.rb"
  rb=$(command -v ruby 2>/dev/null || true)
  # /usr/bin/ruby is the OS copy and needs no RVM; the scanner is kept 2.6-clean
  # so this detector cannot go dark just because the hook's PATH lacks a shim.
  [[ -x "$rb" ]] || rb=/usr/bin/ruby
  if [[ -x "$rb" && -r "$scan" ]]; then
    # [DOC-T.64] THREE outcomes, not two. This used to read the verdict off `$found`
    # alone, so a CRASH of the scanner (an `ArgumentError` on invalid UTF-8 arriving
    # from an arbitrary Bash command is the realistic one) produced empty output —
    # byte-identical to "scanned it, found nothing". The `scanner-dark` lantern below
    # covers only the case its author foresaw (no ruby, unreadable file); it never
    # covered the scanner dying mid-run. stderr stays suppressed on purpose: folding
    # it into `$found` would turn a backtrace into a false DENY.
    found=$(printf '%s' "$cmd" | "$rb" "$scan" 2>/dev/null)
    rc=$?
    if (( rc != 0 )); then
      warn scanner-crash "[bash-guard] zsh_split_scan.rb exited ${rc} — the word-splitting detector CRASHED rather than cleared this command, so its silence means nothing for the rest of this session. Re-run it by hand on the failing input to see the error (stderr is suppressed here to keep a backtrace from reading as a finding)."
    fi
    if [[ -n "$found" ]]; then
      jq -nc --arg f "$found" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:("zsh does not word-split an unquoted scalar — unlike bash. " + $f + ". So the loop body runs once on the whole string (and `set -- $v` leaves $2 empty for ANY input), and whatever check comes next reports success regardless of its input. Fix by making it an array (`v=(a b c); for x in $v`), by splitting explicitly (`${=v}`), or by quoting the element and dropping the re-split. $(subst), globs and arrays are NOT this class and are not flagged.")}}'
      exit 0
    fi
  else
    warn scanner-dark '[bash-guard] zsh_split_scan.rb could not be run (no ruby, or the file is unreadable), so the word-splitting detector is DARK for this session — its silence means nothing. (Fires once per session.)'
  fi
fi

exit 0
