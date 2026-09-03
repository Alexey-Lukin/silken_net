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

# ── --selftest · the guard's own battery (wired as a docs.yml step) ──────────
# This hook DENIES real work, so a rotten detector here is either blocked work
# (false positives) or a dark carrier whose silence reads as safety (false
# negatives) — the same reason zsh_split_scan.rb carries a battery. Cases pin
# BOTH arms of rule E (laundered forms must deny; the clean-`&&` house idiom,
# gate names inside heredoc bodies / -m strings, and each half alone must stay
# silent) plus smoke over the standing deny/warn rules, so a refactor cannot
# silently disable a neighbour. Each case runs with a fresh session id: the
# warn() markers are per-session, and a shared id would let case N suppress
# case N+1's expected warning.
if [[ "${1:-}" == "--selftest" ]]; then
  self="$0"; fails=0; n=0
  # 4th arg = the `run_in_background` flag (default false). It exists because
  # rule F is the one detector whose verdict turns on CONTEXT, not on text: the
  # SAME command must stay silent in the foreground and warn in the background,
  # so a battery that could only send one context could not pin it at all.
  t() {
    local name=$1 expect=$2 cmdstr=$3 bgflag=${4:-false} out got
    n=$((n + 1))
    out=$(jq -nc --arg c "$cmdstr" --arg s "selftest-$$-$n" --argjson b "$bgflag" \
            '{tool_input:{command:$c,run_in_background:$b},session_id:$s}' | bash "$self")
    got="silent"
    if [[ "$out" == *'"permissionDecision":"deny"'* ]]; then
      got="deny"
      [[ "$out" == *"OPS.31"* ]] && got="deny-e"
    elif [[ "$out" == *"additionalContext"* ]]; then
      got="warn"
    fi
    if [[ "$got" == "$expect" ]]; then
      printf '  ✓ %-36s %s\n' "$name" "$got"
    else
      printf '  ✗ %-36s expected %s, got %s\n    out: %s\n' "$name" "$expect" "$got" "$out"
      fails=$((fails + 1))
    fi
  }

  # E-positives — the three measured laundered forms + the newline joiner
  t "E: ;-laundered (08-20 incident)" deny-e \
    $'ruby scripts/docs_band.rb > /tmp/band.log 2>&1; echo "BAND_EXIT=$?"; git add -A && git commit -s -F - <<\'EOF\'\nmsg\nEOF'
  t "E: piped gate (band|tail && commit)" deny-e \
    $'git add -A && ruby scripts/docs_band.rb 2>&1 | tail -2 && git commit -s -F - <<\'MSG\'\nx\nMSG'
  t "E: inverted grep -c gate before push" deny-e \
    'ruby scripts/docs_check.rb 2>&1 | grep -cE "✗|FAIL" && git push origin main'
  t "E: gated commit BUT push after ;" deny-e \
    'ruby scripts/docs_check.rb >/dev/null && git commit -s -m MSG; git push'
  t "E: newline as the joiner" deny-e \
    $'ruby scripts/docs_check.rb >/dev/null 2>&1\ngit push origin main'
  # E-negatives — the exempt idiom and every half alone
  t "E: clean && chain stays silent" silent \
    $'source ~/.rvm/scripts/rvm && rvm use ruby-4.0.6@silken_net >/dev/null && ruby scripts/docs_band.rb >/dev/null && git add docs/ && git commit -s -F - <<\'MSG\'\nx\nMSG'
  # Both anti-false-positive cases are MUTATION-CALIBRATED: with the strips
  # disabled these exact texts flip to a false deny (a heredoc line STARTING
  # with a gate call + a git push after the heredoc; a `-m` string whose `;`
  # puts a gate call at a statement start). Weaker texts — a gate merely
  # mentioned mid-sentence — stayed green even without the strips, because the
  # link-anchoring alone covers them: the first two drafts of these cases were
  # exactly that, i.e. vacuous, and the mutants exposed them.
  t "E: gate named in heredoc body only" silent \
    $'git add -A && git commit -s -F - <<\'EOF\'\nfeat: новий крок\n\nruby scripts/docs_band.rb тепер ловить цей клас\nEOF\ngit push origin main'
  t "E: gate named inside -m string" silent \
    'git commit -s -m "план: спершу гейти; ruby scripts/docs_band.rb обовʼязково; потім пуш" && git push origin main'
  t "E: verify alone (no git)" silent \
    'ruby scripts/docs_band.rb > /tmp/b.log 2>&1; echo "EXIT=$?"'
  t "E: git alone (no gate)" silent \
    'git add -A && git commit -s -m "chore: bump" && git push'
  # F — the SAME text in both contexts, which is the whole point of the rule.
  # The negative arm is not decoration: it is the pin that keeps rule F from
  # degenerating into "a gate followed by echo is suspicious", which would
  # contradict rule B's deliberate foreground exclusion two blocks down.
  t "F: gate backgrounded + trailing echo" warn \
    'bin/rspec --format progress 2>&1 | tail -20; echo "DONE"' true
  t "F: same text in the FOREGROUND stays silent" silent \
    'bin/rspec > /tmp/s.log 2>&1; echo "EXIT=$?"'
  t "F: backgrounded but verdict grepped, not echoed" silent \
    'bin/rspec > /tmp/s.log 2>&1; grep -E "examples," /tmp/s.log' true
  t "F: backgrounded non-gate + echo stays silent" silent \
    'ruby scripts/mem_find.rb --all > /tmp/m.log 2>&1; echo "готово"' true
  # smoke over the standing rules — a refactor must not disable a neighbour
  t "smoke: backtick in commit -m" deny \
    'git commit -m "чи `gates` пройшли"'
  # The MULTI-LINE arm, added 2026-08-22 after walking into it: the opening
  # `-m "` and the backtick sit on different LINES, and grep is per-line — so the
  # guard was blind to exactly the shape a substantive commit message takes. A
  # one-line case cannot pin this; only a message containing a newline can.
  # And the FALSE-POSITIVE arm, bought the same minute: a `-F -` commit whose
  # BODY documents this rule contains the forbidden shape as PROSE, and after
  # flattening it read as the command. `-F -` takes stdin — no shell expansion —
  # so it must stay silent no matter what the message says.
  t "smoke: -F - stays silent even when the body quotes the rule" silent \
    'git commit -F - <<EOF
fix: щось

не пиши git commit -m "…`x`…" ніколи
EOF'
  t "smoke: backtick in MULTI-LINE commit -m" deny \
    'git commit -q -m "fix: header

body with `01_02:177` inside"'
  t "smoke: rg -rn clustered replace" deny \
    'rg -rn "pattern" app/'
  t "smoke: rg -n stays silent" silent \
    'rg -n "pattern" app/'
  t "smoke: unsplit scalar loop (rule C)" deny \
    $'pair="a b"\nfor x in $pair; do echo "$x"; done'
  # ── unquoted `--flag=glob` · both arms ──
  # The negatives matter more than the positives here. Two legal spellings of
  # the SAME fix exist — `--include="*.rb"` and `'--include=*.rb'` — and an
  # anchor written as "dash followed by letters" matches the second one from its
  # inner dash, denying the very form it prescribes. That false positive is what
  # the measurement found by reading top hits, so it is pinned, not assumed.
  # `--audit=$?` is a house idiom (every gate run in this repo ends with one)
  # and must stay silent: `$` is excluded from the value class for that reason.
  t "glob: unquoted --include=*.rb" deny \
    'grep -rn "credit!" app/ --include=*.rb | head -30'
  t "glob: unquoted --include=*.md (the SILENT half — repo root has *.md)" deny \
    'grep -rn "Machine-half" docs/ --include=*.md'
  t "glob: double-quoted value stays silent" silent \
    'grep -rn "x" app/ --include="*.rb"'
  t "glob: whole flag single-quoted stays silent" silent \
    "grep -rn 'dark_cluster_ids' app/ '--include=*.rb' | head"
  t "glob: --audit=\$? is a house idiom, never a glob" silent \
    'bash .claude/hooks/memory_gate.sh --audit; echo "--audit=$?"'
  t "glob: a bare shell glob is legitimate expansion" silent \
    'ls docs/*.md | head'

  t "smoke: gate into tail warns (rule A)" warn \
    'bin/rspec spec/foo_spec.rb 2>&1 | tail -5'
  t "smoke: \$? after pipe warns (rule B)" warn \
    'ruby x.rb | tail -1; echo "EXIT=$?"'

  # ── rule D · all four arms ──
  # This detector reads git STATE, not the command text, so a case built from a
  # string alone is vacuous: on a clean tree the deny arm is unreachable and the
  # battery would be green for the wrong reason. The fixture therefore makes a
  # genuinely dirty tracked path — `git add -N` registers intent-to-add, so
  # `git diff --numstat` reports lines against an empty index entry, and no
  # commit is involved. `trap` guarantees removal even if a case aborts.
  dfix=".bashguard_selftest_dirty.tmp"
  if git rev-parse --git-dir >/dev/null 2>&1; then
    trap 'git rm --cached -q "$dfix" 2>/dev/null; rm -f "$dfix"' EXIT
    printf 'a\nb\n' > "$dfix"
    git add -N "$dfix" 2>/dev/null
    t "D: checkout of a DIRTY tracked file denies" deny \
      "git checkout $dfix"
    t "D: declared intent (token) stays silent" silent \
      "git checkout $dfix  # discard-dirty"
    t "D: backup taken in the SAME call stays silent" silent \
      "cp $dfix /tmp/f.bak && git checkout $dfix"
    git rm --cached -q "$dfix" 2>/dev/null
    rm -f "$dfix"
    trap - EXIT
    # The false-positive arm: a path with NO uncommitted lines must never deny,
    # or every legitimate revert becomes blocked work.
    t "D: checkout of a CLEAN file stays silent" silent \
      "git checkout README.md"
  fi

  if (( fails > 0 )); then
    echo "bash_verify_guard --selftest: ${fails}/${n} FAILED"
    exit 1
  fi
  echo "bash_verify_guard --selftest: OK (${n} cases — rules D, E and F all arms + smoke over A/B/C/backtick/rg)"
  exit 0
fi

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
session=$(printf '%s' "$input" | jq -r '.session_id // "nosession"' 2>/dev/null)
# Rule F's discriminator: ONE text has opposite verdicts in the two contexts.
bg=$(printf '%s' "$input" | jq -r '.tool_input.run_in_background // false' 2>/dev/null)
[[ -n "$cmd" ]] || exit 0

# ── BLOCK · backtick inside `git commit -m "…"` ──────────────────────────────
# 2 calls in 17,206 — and the damage is in this repo's history permanently: a
# commit message whose sentence lost its subject because `…` ran as a command
# substitution, returned empty, and vanished silently. Nothing fails, nothing
# warns, and git history cannot be rewritten after a push.
# The dominant idioms are already safe and stay silent: `-F -` (587 uses),
# `-m "$(cat <<'QUOTED')"` (110), `$(printf …)`, and escaped \`.
# 🔴 FLATTEN FIRST. `grep` works per LINE, and a substantive `-m "…"` is
# MULTI-LINE: the opening `-m "` sits on line 1 while the backtick sits five
# lines down, so the pattern never matched the very shape it exists to catch.
# Measured by walking into it 2026-08-22 — a memory commit lost every one of its
# `NN_NN:NNN` coordinates, silently, with this guard installed and green.
# ⚠️ Flattening created a FALSE POSITIVE the first time it ran: a `-F -` commit
# whose BODY described this very rule matched, because after flattening the
# prose «-m "…`x`…»» looks like the command. A rule that documents a forbidden
# form necessarily contains it. `-F -` is safe by construction (stdin, no shell
# expansion), so it short-circuits before the flattened match.
if printf '%s' "$cmd" | grep -qE 'git[[:space:]]+commit[^|;]*-F[[:space:]]+-'; then
  :
else
_flat=$(printf '%s' "$cmd" | tr '\n' ' ')
if printf '%s' "$_flat" | grep -qE 'git[[:space:]]+commit[^|;]*-m[[:space:]]+"[^"]*[^\\]`'; then
  if ! printf '%s' "$_flat" | grep -qE -- '-m[[:space:]]+"\$\('; then
    jq -nc --arg r 'Backtick inside git commit -m "…": the shell will RUN it as a command substitution and silently drop the text — it does not fail, and after a push the message cannot be fixed. This repo already carries one such sentence, meaningless forever. Use `git commit -F -` with a heredoc instead.' \
      '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
    exit 0
  fi
fi
fi

# ── BLOCK · `rg -<cluster>` where `r` is not the last letter ─────────────────
# `-r` is `--replace`, and in a CLUSTERED short-flag token it swallows the
# remaining letters as the replacement STRING: `rg -rn "pat" path` parses as
# `--replace=n`, so every match is printed as the literal `n` and the real text
# never reaches the eye. Nothing errors. The output looks like a normal result
# set, which is the whole danger — the corruption is in the CONTENT, not in the
# exit code, and it feeds whatever conclusion the caller was measuring.
#
# Measured over 22,064 recorded Bash calls: 315 use `rg`, 3 use the legitimate
# spaced `-r <replacement>` (untouched by this anchor), and 9 match this
# signature — ALL NINE are `rg -rn`, i.e. precision 9/9. For scale, the backtick
# rule above ships at 2 findings in 17,206. Six of the nine landed in the last
# two days, so the rate is rising, not decaying.
#
# It is a BLOCK rather than a warn because the failure has no symptom: a warn
# arrives beside output the reader already believes. Prose did not hold it —
# the rule stands as item 6 in the memory corpus and was re-tripped four times
# in one session by the author who had just read that file.
#
# Anchor is the FLAG POSITION, not "a dash followed by letters": the loose form
# matched `-Users` inside `/private/tmp/…/-Users-oleksiilukin-…` and reported
# path segments as findings. Found by reading the top hits, never visible in the
# total — the measurement instrument had the same class of defect it measures.
# ⚠️ Flag and `rg` must sit in the SAME segment. Two separate conditions would
# deny `grep -rn "x" . ; rg -n "y"`, where `-r` is grep's legitimate recursion —
# and the measurement above was segment-scoped, so a whole-command guard would
# ship something other than what was measured.
if printf '%s' "$cmd" | grep -qE '(^|[;&|])[[:space:]]*rg[[:space:]]+([^;&|]*[[:space:]]+)?-[a-zA-Z]*r[a-zA-Z]+([[:space:]]|$)'; then
  jq -nc --arg r 'In `rg`, `-r` is --replace, and in a clustered flag token it eats the remaining letters as the replacement string: `rg -rn "pat"` means --replace=n, so every match prints as the literal "n" and the real text is never shown. Nothing fails and the exit code is 0 — the corruption is in the OUTPUT you are about to read. ripgrep is recursive by default, so `-r` is never what you want here: drop it (`rg -n`), or pass a real replacement with a space (`rg -r "text" -n`).' \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
fi

# ── BLOCK · `--flag=<glob>` left UNQUOTED ────────────────────────────────────
# zsh expands a glob in an argument BEFORE the program sees it, and — unlike
# bash — a glob that matches nothing is FATAL: the whole command dies without
# running. `grep -rn "x" app/ --include=*.rb` never reaches grep.
#
# Both outcomes are wrong, and the second is the dangerous one:
#   · cwd holds no matching file → `no matches found: *.rb`, nothing runs;
#   · cwd DOES hold one → the glob expands, so grep receives
#     `--include=CLAUDE.md` plus the remaining .md files as extra SEARCH
#     TARGETS. Exit 0, plausible output, silently wrong scope.
# The repo root is exactly this trap: no *.rb or *.yml (loud), nine *.md
# (silent). So the same typo is noisy or invisible depending on the extension.
#
# Measured over 40,231 recorded Bash calls: 131 carry an unquoted `--flag=glob`
# and 121 of them (92.4%) died with «no matches found»; the other 10 are the
# silent half, not survivors. The quoted form — the fix — appears 722 times, so
# the house idiom is already correct and this denies only the slips. For scale,
# the rg rule above shipped at 9 findings in 22,064 and the backtick rule at 2
# in 17,206; this is the single largest shell-failure class in the corpus, at
# 118 of 227 «no matches found» incidents.
#
# It is a BLOCK, not a warn, for the reason the whole corpus keeps re-learning:
# prose does not fire at the moment of typing. `--include=*.rb` alone accounts
# for 132 occurrences while the memory file on zsh gotchas — 40 kB, fourteen
# items — never named this class at all, because each single instance was cheap
# and got retyped instead of recorded.
#
# Quoting is stripped FIRST rather than matched around: both `--include="*.rb"`
# and `'--include=*.rb'` are legal, and an anchor that reads "a dash followed by
# letters" matches the second one starting at its inner dash — the same defect
# class the rule measures, which is why the negative controls carry both forms.
# `$` is excluded from the value so `--audit=$?` (a house idiom) stays silent.
_unq=$(printf '%s' "$cmd" | sed -e "s/'[^']*'//g" -e 's/"[^"]*"//g')
if printf '%s' "$_unq" | grep -qE '(^|[[:space:]])--?[a-zA-Z][a-zA-Z0-9_-]*=[^[:space:];&|`$()]*[*?[][^[:space:];&|`$()]*'; then
  jq -nc --arg r 'An unquoted glob inside `--flag=…` (e.g. `--include=*.rb`) is expanded by zsh before the program runs, and a glob that matches nothing is FATAL here — unlike bash, the command dies with «no matches found» and nothing executes. When it DOES match (the repo root has nine *.md files), it is worse: grep receives `--include=CLAUDE.md` and the rest as extra search targets, so you get exit 0 and a silently wrong scope. Quote it: --include="*.rb". Measured: 131 such calls in this corpus, 121 killed outright.' \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
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

# The verdict-emitting gate vocabulary — shared by rule A (a gate truncated
# into head/tail) and rule E (a gate laundered past git commit/push), so it is
# defined OUTSIDE the PIPESTATUS conditional below: a command that merely
# mentions `pipefail` skips A/B, and rule E must still see the list.
# Report generators are deliberately absent: stan_audit.rb and mem_find.rb have
# no `exit 1` path at all, so slicing them is querying, not truncating a verdict.
gate='(bin/rspec|bundle exec rspec|bin/rubocop|bundle exec rubocop|bin/brakeman|bin/bundler-audit|bin/ci|make -C firmware/test|forge (test|build|coverage)|ruff check|pytest|bin/rails (docs:|tracker:|gaia:|zeitwerk:|spec)|rake (docs:|tracker:))'

# Already reading the pipeline's real status → silent. 222 calls do this, and
# three of the first five false positives measured were exactly this case.
if ! printf '%s' "$cmd" | grep -qE 'PIPESTATUS|pipestatus|pipefail'; then

  # ── A · a GATE truncated into head/tail (9.09% naive→scoped, ~97% precise) ──
  # The discriminator is the PRODUCER, not the pipe: of 11,712 head/tail
  # pipelines, 5,876 are grep and 283 ls — all legitimate. So the producer must
  # be an actual verdict-emitting gate AND stand at the START of its statement;
  # that anchor is what kills the measured false-positive class, where the word
  # matched a FILENAME (`grep -n … config/brakeman.ignore | head`).
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
  # ✅ The gap this block used to declare (foreground-only exclusion, background
  # verdict laundered past the harness notice) is CLOSED by rule F below — the
  # measurement it asked for was taken 2026-08-27. Keep this exclusion as is:
  # in the FOREGROUND `cmd > log 2>&1; echo "EXIT=$?"` is exactly right, and the
  # discriminator is the flag, not the text. Rule-home for the class: memory
  # `feedback_verify_gate_exit_code`, fourth family (a).
  if { printf '%s' "$cmd" | grep -qE '[^|]\|[^|][^;]*;[[:space:]]*echo[^;]*\$\?' ||
       printf '%s' "$cmd" | grep -qE '[^>&<]&[[:space:]]*;[[:space:]]*echo[^;]*\$\?' ; } &&
     ! printf '%s' "$cmd" | grep -qE '\|[[:space:]]*grep[^|;]*;[[:space:]]*echo[^;]*\$\?' ; then
    warn exit-after-pipe '[bash-guard] `$?` after a pipe or a background start reports the LAST element, and head/tail/`&` always exit 0 — so this reads success no matter what happened upstream. Use $pipestatus[1] — this shell is zsh, where the array is lowercase and 1-INDEXED; ${PIPESTATUS[0]} expands to an empty string, so a check built on it silently compares against nothing. Or run the command unpiped and echo $? on its own line. (Fires once per session.)'
  fi
fi

# ── F · WARN · a verdict-bearing gate BACKGROUNDED behind a trailing `echo` ──
# The one shape whose verdict flips with CONTEXT rather than with text, which is
# why it needed the flag and not a better regex. In the foreground
# `gate > log 2>&1; echo "EXIT=$?"` is correct and stays silent (rule B above).
# Backgrounded, the harness reports the STATEMENT CHAIN — i.e. the echo's 0 —
# so the completion notice reads "exit code 0" about a run that failed.
# Measured 2026-08-27 over 181 session transcripts: 525 unique background Bash
# calls, 305 carrying this file's `gate` vocabulary, and 169 of those (55.4%)
# ending in a trailing `echo`. 32 kept the verdict NOWHERE but inside the log.
# ⚠️ A 55% base rate would be noise for a per-call warning; it is not for a
# per-SESSION one — warn() is keyed by session+class, so this fires once in
# exactly the sessions that background a gate, which is the population at risk.
# ⚠️ Two ceilings, named: (1) `grep` works per LINE, so a mid-command `; echo`
# that ends its own line also matches — accepted, the advice stays true either
# way; (2) the vocabulary is `gate` verbatim, NOT widened, because rules A and E
# share it and widening it would change their measured behaviour unmeasured —
# so a backgrounded `ruby scripts/docs_band.rb` is out of scope here by design.
if [[ "$bg" == "true" ]] &&
   printf '%s' "$cmd" | grep -qE "(^|[;&]|&&|\|\||^[[:space:]]*)[[:space:]]*(env [^|;]* )?${gate}" &&
   printf '%s' "$cmd" | grep -qE ';[[:space:]]*echo[^;|]*$' ; then
  warn bg-verdict '[bash-guard] This gate runs in the BACKGROUND and its last statement is an echo — so the completion notice will carry the echo status (0), never the gate. Measured here: 169 of 305 background gate-runs have this shape, and one of them announced "exit code 0" for an rspec run that had died on the coverage floor with 2. Read the verdict out of the .output file yourself (grep for "examples," and for "SimpleCov"/"EXIT="). An EXIT= line captured INSIDE the log is not the notice — the notice still says 0. (Fires once per session.)'
fi

# ── D · BLOCK · `git checkout <file>` while that file carries UNCOMMITTED edits ──
# Rule home: memory feedback_verify_before_commit («reverse Edit, never checkout»)
# — written there 2026-08-04. `git checkout <path>` restores the file from the
# index, so it DESTROYS any uncommitted edit living in it: no prompt, no stash,
# nothing to `git revert`. Measured over the corpus: 40 `git checkout` calls, 22
# against file paths, ≥2 destructive — but whether a given one is destructive
# depends on the file's INDEX/WD state, which no regex sees. This hook CAN see
# it: it asks git at call time, so it fires only when there genuinely are
# uncommitted lines to lose, and names how many.
#
# 🔴 THIS IS THE SECOND deliberate override of the file's false-negative bias
# (rule C is the first), and it was bought with FIVE relapses, the last on
# 2026-08-28. It shipped as a WARN and the WARN was measured insufficient:
# `additionalContext` arrives together with the result of the ALREADY-EXECUTED
# command, so by the time the sentence is read the edits are gone — the 2026-08-28
# instance ate 43 uncommitted lines of the session's own fix and survived only
# because the file was still in context (reverse-Edit, one minute). A warning that
# can only ever arrive post-mortem is not a carrier for an IRREVERSIBLE loss; the
# nag-cost argument in the header does not apply either, because the detector is
# state-anchored (~0.5 firings/day corpus-wide, every one a real decision point).
#
# The intent must be DECLARED, never guessed — the same stance as the Solidity
# `expectRevert` gate (a bare "any revert" has to say `expectPartialRevert`).
# Two declared exits, both silent:
#   1. `discard-dirty` anywhere in the command — "I checked; the dirt here IS
#      what I mean to throw away". One token, and the decision stays conscious.
#   2. a `cp` of that same path in the SAME call — the backup makes it reversible,
#      which is the mutation-cycle idiom the rule prescribes in the first place.
# `-b`, branch names, `stash`, and clean files stay silent by construction.
if printf '%s' "$cmd" | grep -qE 'git[[:space:]]+checkout[[:space:]]' &&
   ! printf '%s' "$cmd" | grep -qE 'git[[:space:]]+checkout[[:space:]]+-b'; then
  ckpaths=$(printf '%s' "$cmd" | grep -oE 'git[[:space:]]+checkout[[:space:]]+(--[[:space:]]+)?[^;&|]+' \
            | sed -E 's/git[[:space:]]+checkout[[:space:]]+(--[[:space:]]+)?//' | tr ' ' '\n' \
            | grep -E '\.[a-z]{1,4}$' | head -10)
  if [[ -n "$ckpaths" ]]; then
    dirty=""
    while IFS= read -r p; do
      [[ -n "$p" ]] || continue
      n=$(git diff --numstat -- "$p" 2>/dev/null | awk '{s+=$1+$2} END {print s+0}')
      (( n > 0 )) || continue
      # Declared exit 2: the same path is also handed to `cp` in this very call,
      # i.e. a backup is being taken alongside — the loss is reversible.
      if printf '%s' "$cmd" | grep -qE '(^|[;&|[:space:]])cp[[:space:]]' &&
         (( $(printf '%s' "$cmd" | grep -oF "$p" | wc -l) >= 2 )); then
        continue
      fi
      dirty="${dirty}${p} (${n} uncommitted line(s)); "
    done <<< "$ckpaths"
    # Declared exit 1: an explicit token — the decision is conscious and recorded.
    if [[ -n "$dirty" ]] && ! printf '%s' "$cmd" | grep -qF 'discard-dirty'; then
      jq -nc --arg r "git checkout will silently DESTROY uncommitted edits: ${dirty}— no prompt, no stash, nothing to revert, and this hook can only speak BEFORE the call, never after. Relapsed five times with the rule written down, which is why this denies instead of warning. To undo a mutation or an experiment: restore from a cp-backup, or apply a reverse Edit. If the dirty state IS what you mean to discard, declare it — add the token \`discard-dirty\` to the command (a comment is enough), or take the backup in the same call (\`cp <path> \"\$T/f.bak\" && git checkout <path>\`). Rule home: memory feedback_verify_before_commit." \
        '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
      exit 0
    fi
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

# ── E · BLOCK · a gate LAUNDERED past `git commit`/`git push` in the same call ──
# [OPS.31] Measured 2026-08-20 over 31,464 recorded Bash calls with THIS block's
# own classifier: 220 calls combine a verdict-emitting gate with git commit/push.
# 203 are laundered — the verdict does not gate the git step: 193 join them with
# `;`/newline (the gate's exit is echoed, then commit runs REGARDLESS of it), and
# 10 pipe the gate itself (`band 2>&1 | tail -2 && commit` — tail's exit replaces
# the verdict; one was `| grep -cE "✗|FAIL" && push`, INVERTED: finding failures
# returns 0). Both incidents that motivated the rule — 2026-08-16 and 2026-08-20,
# each pushing a red docs band to main — sit in that population, and prose had
# already relapsed twice in four days with the rule written down. The remaining
# 17 combos join gate→git with a clean unpiped `&&`: mechanically honest (a red
# gate STOPS the chain), the house campaign idiom — ⚖️ founder 2026-08-20: they
# stay SILENT; deny the laundered forms only.
# Heredoc bodies and `-m "…"` payloads are stripped FIRST: commit messages here
# routinely NAME gates («повна сюїта bin/rspec 8403/0»), and without the strip
# every such message would read as a gate invocation.
# Declared ceilings (bias to false negatives, per this file's stance): a
# statement carrying its own clean gate exempts its git step even when an
# EARLIER gate in the call was laundered (half-gated, 1 measured); a gate that
# runs AFTER the git step in the same && chain is a post-hoc check, not this
# class (2 measured); text following the first heredoc opener is dropped, so a
# laundered combo living entirely BELOW a heredoc is invisible (0 measured).
if printf '%s' "$cmd" | grep -qE 'git[[:space:]]+(commit|push)\b'; then
  hd=$(printf '%s\n' "$cmd" | grep -nE "<<-?~?[[:space:]]*['\"]?[A-Za-z_]" | head -1 | cut -d: -f1)
  if [[ -n "$hd" ]]; then ecmd=$(printf '%s\n' "$cmd" | head -n "$hd"); else ecmd=$cmd; fi
  ecmd=$(printf '%s' "$ecmd" | sed -E "s/-m[[:space:]]+\"[^\"]*\"/-m MSG/g; s/-m[[:space:]]+'[^']*'/-m MSG/g")
  egate="((env[[:space:]]+[^[:space:]]+[[:space:]]+)?([A-Z_]+=[^[:space:]]+[[:space:]]+)*)?(${gate}|ruby[[:space:]]+scripts/(docs_band|docs_check|model_doc_sync)\.rb)"
  if printf '%s' "$ecmd" | grep -qE "$egate"; then
    verdict=""
    gate_seen=""
    while IFS= read -r st; do
      links=${st//&&/$'\n'}
      links=${links//||/$'\n'}
      st_gate=""; st_git=""; st_piped=""
      while IFS= read -r lk; do
        if printf '%s' "$lk" | grep -qE "^[[:space:]]*${egate}"; then
          st_gate=1
          printf '%s' "$lk" | grep -q '|' && st_piped=1
        fi
        printf '%s' "$lk" | grep -qE '^[[:space:]]*git[[:space:]]+(commit|push)\b' && st_git=1
      done <<< "$links"
      if [[ -n "$st_git" && -z "$st_gate" && -n "$gate_seen" && "$verdict" != "piped" ]]; then verdict="semicolon"; fi
      if [[ -n "$st_gate" && -n "$st_git" && -n "$st_piped" ]]; then verdict="piped"; fi
      [[ -n "$st_gate" ]] && gate_seen=1
    done < <(printf '%s\n' "$ecmd" | tr ';' '\n')
    if [[ -n "$verdict" ]]; then
      jq -nc --arg r "A verdict-emitting gate and git commit/push share this call, but the verdict does NOT gate the git step (${verdict} form): they are joined by \`;\`/newline, or the gate is piped so tail/grep's exit replaces its own. The verdict arrives only AFTER the whole call has run — reading it then is a report about a consequence, not verification, and this exact shape pushed a red docs band to main twice (2026-08-16, 2026-08-20). Run the gate in its OWN call and read the verdict first; or use the sanctioned single-call form — every step joined by a clean unpiped \`&&\`, so a red gate mechanically STOPS the chain. [OPS.31]" \
        '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
      exit 0
    fi
  fi
fi

exit 0
