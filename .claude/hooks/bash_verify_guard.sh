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
# Three rules were MEASURED AND DROPPED and stay dropped:
#   · `cd` persistence — real, but the harness ALREADY carries it: 95.7% of calls
#     ending outside the repo print "Shell cwd was reset to …". A hook here would
#     duplicate a live carrier and add ~1,272 firings of pure noise.
#   · widening the GATE VOCABULARY below to our own verdict-emitting scripts
#     (`ruby scripts/docs_check.rb`, `scripts/docs_band.rb`). The blindness is
#     REAL — both return a verdict by exit code (`exit overall` and `exit 1`), so
#     rule A does not see them truncated — and it was refused anyway, ⚖️ founder
#     2026-09-21: 292 of their calls pipe into head/tail across 181 sessions,
#     i.e. ~1.6 new naggings per session against a stance that buys its
#     credibility with silence. ⛔ The refusal is about the RATE, not about the
#     blindness, so do not re-open it on the blindness alone — re-open it on a
#     NEW measurement of that rate. Provenance: 00_07 OPS.39 §🗄️.
#   · squiggly heredoc `<<~` in a patch script (it strips the shared indent from
#     the anchor AND the replacement, so text lands at column 0). Measured over
#     161 sessions: 251 indented `<<~` bodies, only 4 meant for column 0 — ~247
#     firings of noise, because no predicate tells an indented insert from a
#     top-level one (narrowing it to "Python inside" does not help: a top-level
#     Python block also belongs at column 0). Carriers live downstream — rubocop
#     on pre-push, ruff / IndentationError, the diff — and the recipe is
#     `<<-'RB'` in edit scripts, never `<<~`. Re-proposed once without knowing
#     this, because the refusal was recorded only in memory.
#
# A FOURTH was dropped and then OVERTURNED, and the reversal is the more useful
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
# BOTH arms of rule E (laundered forms must deny, a git step fed by a pipe included;
# the clean-`&&` house idiom, gate names inside heredoc bodies / -m strings / any
# quoted text holding a separator, and each half alone must stay
# silent) plus smoke over the standing deny/warn rules, so a refactor cannot
# silently disable a neighbour. Each case runs with a fresh session id: the
# warn() markers are per-session, and a shared id would let case N suppress
# case N+1's expected warning.
# 🔴 «Fresh» held only WITHIN one run: the id is `selftest-<PID>-<n>`, the markers
# were never removed, and a PID recycles — so a later run whose PID matched an old
# one found its warn markers already there and read every expected warning as
# silence. Measured 2026-09-25: 2,038 orphan markers in the local TMPDIR, and the
# band's red self-test ran as a PID that owned six of them. CI never sees it (a
# fresh machine), which is exactly why it read as «local red, CI green». Hence the
# battery gets its OWN TMPDIR, removed on exit — every child inherits it.
if [[ "${1:-}" == "--selftest" ]]; then
  TMPDIR=$(mktemp -d "${TMPDIR:-/tmp}/bashguard-selftest.XXXXXX"); export TMPDIR
  # Rule H reads the REAL working tree unless told otherwise, which would make every
  # case that merely contains `git add` depend on what is mid-computation. Default the
  # battery to CLEAN; the H block exports the dirty value for its own arm.
  export BASHGUARD_CACHE_DIRTY=clean
  trap 'rm -rf "$TMPDIR"' EXIT
  self="$0"; fails=0; n=0
  # 4th arg = the `run_in_background` flag (default false). It exists because
  # rule F is the one detector whose verdict turns on CONTEXT, not on text: the
  # SAME command must stay silent in the foreground and warn in the background,
  # so a battery that could only send one context could not pin it at all.
  # 5th arg `noawk` / `nosed` runs the hook with that tool failing (exit 127): rule E must
  # then judge the raw call, never nothing [OPS.43].
  # `T_SID` (set, then unset) runs several cases in ONE session — the only way to pin
  # what a call leaves behind for the next one [OPS.45].
  t() {
    local name=$1 expect=$2 cmdstr=$3 bgflag=${4:-false} broken=${5:-} out got
    n=$((n + 1))
    out=$(jq -nc --arg c "$cmdstr" --arg s "${T_SID:-selftest-$$-$n}" --argjson b "$bgflag" \
            '{tool_input:{command:$c,run_in_background:$b},session_id:$s}' |
          if [[ -n "$broken" ]]; then
            bash -c "${broken#no}() { return 127; }; export -f ${broken#no}; exec bash \"\$0\"" "$self"
          else bash "$self"; fi)
    got="silent"
    if [[ "$out" == *'"permissionDecision":"deny"'* ]]; then
      got="deny"
      [[ "$out" == *"OPS.31"* ]] && got="deny-e"
    elif [[ "$out" == *"additionalContext"* ]]; then
      got="warn"
      [[ "$out" == *"OPS.41"* ]] && got="warn-i"
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
    $'source ~/.rvm/scripts/rvm && rvm use "$(cat .ruby-version)@silken_net" >/dev/null && ruby scripts/docs_band.rb >/dev/null && git add docs/ && git commit -s -F - <<\'MSG\'\nx\nMSG'
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
  # OPS.40 — the memory pair, both arms. The positives are the corpus forms (the
  # 2026-09-23 incident shape and its piped sibling); the two negatives are the
  # CROSS-SUBJECT forms the prescribed widening denied, and they are the pins that
  # keep the pairing by subject from collapsing back into one shared vocabulary.
  t "E/mem: --audit ;-laundered before git -C commit" deny-e \
    'bash .claude/hooks/memory_gate.sh --audit >/dev/null 2>&1; echo "EXIT=$?"; M=/x/memory; git -C "$M" add -A && git -C "$M" commit -q -m msg'
  t "E/mem: --audit piped into tail before git -C commit" deny-e \
    'M=/x/memory; bash .claude/hooks/memory_gate.sh --audit 2>&1 | tail -3 && git -C $M commit -q -m msg'
  t "E/mem: clean && from --audit to git -C stays silent" silent \
    'M=/x/memory; bash .claude/hooks/memory_gate.sh --audit >/dev/null 2>&1 && git -C $M add a.md && git -C $M commit -q -m msg'
  t "E/mem: memory audit before a REPO commit stays silent" silent \
    'bash .claude/hooks/memory_gate.sh --audit >/dev/null 2>&1; echo "A=$?"; git add docs/x.md && git commit -s -m msg'
  t "E/mem: repo gate piped before a MEMORY commit stays silent" silent \
    'M=/x/memory; bin/rspec spec/x_spec.rb 2>&1 | grep -E "examples," && git -C $M commit -q -m msg'
  # The fix-forward's own arms (2026-10-04, after the adversary): the incident shape
  # BELOW a heredoc, the `cd` form that is the majority of memory commits, and a repo
  # gate laundered below a heredoc must deny; a repo gate before a corpus commit made
  # through `cd`, and a memory audit before a `git -C` on a NON-corpus dir, must not.
  t "E/mem: --audit laundered BELOW a heredoc (09-23 shape)" deny-e \
    $'M=/x/memory; python3 - "$M" <<\'PY\'\nprint(1)\nPY\nbash .claude/hooks/memory_gate.sh --audit >/dev/null 2>&1; echo "audit=$?"; git -C $M add a.md && git -C $M commit -q -m msg'
  t "E/mem: cd into the corpus, then plain git commit" deny-e \
    'M=/x/memory; bash .claude/hooks/memory_gate.sh --audit >/dev/null 2>&1; echo "A=$?"; cd $M && git add -A && git commit -q -m msg'
  t "E: repo gate laundered BELOW a heredoc denies" deny-e \
    $'python3 - <<\'PY\'\nprint(1)\nPY\nruby scripts/docs_check.rb >/dev/null 2>&1\ngit add docs/x.md && git commit -s -q -m msg'
  t "E/mem: repo gate before a cd-into-corpus commit stays silent" silent \
    'M=/x/memory; ruby scripts/docs_band.rb >/dev/null 2>&1; echo "B=$?"; cd "$M" && git add a.md && git commit -q -m msg'
  t "E/mem: memory audit before git -C <non-corpus> push stays silent" silent \
    'bash .claude/hooks/memory_gate.sh --audit >/dev/null 2>&1; echo "A=$?"; git -C /Users/x/silken_net push origin main'
  # OPS.43 — a git step also starts a PIPE ELEMENT (global flags allowed), and the split
  # runs on a MASKED copy. Every case below is the kill-case of its own in-place mutant:
  # the positives deny only through the piece they name, the negatives stay silent only
  # because a quoted token holding a separator is blanked. The three «as 61bcc2771» pins
  # are the regressions of the shell lexer withdrawn 2026-10-24 — they must keep the
  # verdict the unmasked split gave. `docs_check.rb` below is a gate NAME in the input, not the lane (`docs_band.rb`).
  t "E: ;-laundered, printf | git commit (10-23)" deny-e \
    $'ruby scripts/docs_check.rb >/dev/null 2>&1; echo "C=$?"; git add docs/x.md && printf \'%s\\n\' \'docs: x\' \'\' \'body\' | git commit -q -s -F -'
  t "E: |& into git commit" deny-e \
    $'ruby scripts/docs_check.rb >/dev/null 2>&1; echo "C=$?"; printf \'%s\\n\' msg |& git commit -F -'
  t "E: pipe without spaces (msg|git commit)" deny-e \
    $'ruby scripts/docs_check.rb >/dev/null 2>&1; echo "C=$?"; printf msg|git commit -F -'
  t "E/mem: ;-laundered --audit, printf | git -C commit" deny-e \
    $'bash .claude/hooks/memory_gate.sh --audit >/dev/null 2>&1; echo "A=$?"; M=/x/memory; git -C $M add a.md && printf \'%s\\n\' msg | git -C $M commit -q -F -'
  # (`docs_check.rb` in these fixtures is a gate NAME in the input, not the lane — the band is `ruby scripts/docs_band.rb`; CHECK F, OPS.25)
  t "E: git -c k=v commit" deny-e \
    'ruby scripts/docs_check.rb >/dev/null 2>&1; echo "C=$?"; git -c user.name=x commit -m MSG'
  t "E: git --no-pager push" deny-e \
    'ruby scripts/docs_check.rb >/dev/null 2>&1; echo "C=$?"; git --no-pager push origin main'
  t "E: git -P push" deny-e \
    'ruby scripts/docs_check.rb >/dev/null 2>&1; echo "C=$?"; git -P push origin main'
  t "E/mem: git --git-dir <corpus> commit" deny-e \
    'bash .claude/hooks/memory_gate.sh --audit >/dev/null 2>&1; echo "A=$?"; git --git-dir /x/memory/.git commit -q -m msg'
  t "E/mem: git --git-dir=<corpus> commit" deny-e \
    'bash .claude/hooks/memory_gate.sh --audit >/dev/null 2>&1; echo "A=$?"; git --git-dir=/x/memory/.git commit -q -m msg'
  # (`docs_check.rb` in these fixtures is a gate NAME in the input, not the lane — the band is `ruby scripts/docs_band.rb`; CHECK F, OPS.25)
  t "E: git commit inside \"\$( )\" is code" deny-e \
    'ruby scripts/docs_check.rb >/dev/null 2>&1; echo "C=$?"; echo "$(printf msg | git commit -F -)"'
  t "E: bash -c \"…\" body is code (gate inside, push outside)" deny-e \
    'bash -c "cd /x && ruby scripts/docs_check.rb 2>&1 | tail -1"; git push origin main'
  t "E: quoted 'git add|git commit' is a pattern" silent \
    $'ruby scripts/docs_check.rb >/dev/null 2>&1; echo "C=$?"; rg -c \'git add|git commit -F\' transcripts/'
  t "E: quoted '| git commit' is a pattern" silent \
    $'ruby scripts/docs_check.rb >/dev/null 2>&1; echo "C=$?"; grep -c \'| git commit -F\' ~/x.jsonl'
  t "E: ; in a '…' message names a gate" silent \
    $'git add docs/x.md && printf \'%s\\n\' \'docs: x\' \'\' \'зелено; ruby scripts/docs_band.rb 0 FAIL\' | git commit -q -s -F -'
  t "E: ; in a \"…\" message names a gate" silent \
    $'git add f && printf \'%s %s\\n\' fix: "x; ruby scripts/docs_band.rb green" | git commit -F -'
  t "E: ; in a \$'…\\'…' message names a gate" silent \
    $'git add f && printf $\'fix: it\\\'s; ruby scripts/docs_band.rb ok\\n\' | git commit -F -'
  t "E: ; across a '\\'' join names a gate" silent \
    $'git add f && printf \'%s\\n\' \'it\'\\\'\'s; ruby scripts/docs_band.rb ok\' | git commit -F -'
  t "E: a newline in a '…' message starts a gate" silent \
    $'git add f && printf \'%s\\n\' \'fix: x\nruby scripts/docs_band.rb 0 FAIL\' | git commit -F -'
  t "E: ; in a printf message, clean && gate" silent \
    $'ruby scripts/docs_band.rb > /tmp/b.log 2>&1 && printf \'%s\\n\' "fix: x" "" "кожен знімає лише свій; подія інша" > /tmp/m.txt && git add docs/x.md && git commit -s -F /tmp/m.txt'
  t "E: as 61bcc2771 — gate with \$( | ) piped, && push" deny-e \
    'bin/rspec $(git diff --name-only main -- spec | grep _spec.rb) 2>&1 | grep -E "examples," && git push origin main'
  t "E: as 61bcc2771 — gate with \`…\` piped, && commit" deny-e \
    'ruby scripts/docs_check.rb `cat docs.txt` 2>&1 | tail -2 && git commit -s -m x'
  t "E: as 61bcc2771 — && commit || true stays silent" silent \
    'bin/rspec spec/x_spec.rb && git add -A && git commit -s -m x || true'
  t "E: as 61bcc2771 — cd inside \$( ) names no subject" deny-e \
    'ruby scripts/docs_check.rb >/dev/null 2>&1; echo "C=$?"; M=/x/memory; N=$(cd $M && ls | wc -l); git add f && git commit -q -m msg'
  t "E: as 61bcc2771 — cd inside ( ) names no subject" deny-e \
    'ruby scripts/docs_check.rb >/dev/null 2>&1; echo "C=$?"; (cd /x/memory && ls); git add f && git commit -q -m msg'
  t "E: awk fails → the raw call is judged" deny-e \
    $'ruby scripts/docs_band.rb > /tmp/band.log 2>&1; echo "BAND_EXIT=$?"; git add -A && git commit -s -F - <<\'EOF\'\nmsg\nEOF' false noawk
  t "E: sed fails → the raw call is judged" deny-e \
    'ruby scripts/docs_check.rb >/dev/null 2>&1; echo "C=$?"; git push origin main' false nosed
  # Round 3 of the adversary attacked the mask itself: a STRAY quote pairs with the next one
  # anywhere and blanks a real separator with the git step or the gate. A3 · J3 · Q1 deny only
  # because a blanked token holding `; git push` stays code; C2 only because `-m "…\"…"` is
  # stripped escape-aware; H1 stays silent only because an ESCAPED backtick is not code. The
  # last case is J1 — the one stray quote the mask still loses (declared above) — padded past
  # 8 KB: there the call is split unmasked and denies exactly as before the mask.
  t "E: A3 comment пам'ять, then push; echo 'ok'" deny-e \
    $'ruby scripts/docs_band.rb >/dev/null 2>&1; echo "B=$?"  # пам\'ять\ngit push origin main; echo \'ok\''
  t "E: J3 two comment apostrophes around a push" deny-e \
    $'ruby scripts/docs_band.rb >/dev/null 2>&1  # it\'s\ngit push origin main  # don\'t'
  t "E: C2 -m \"…\\\"q\\\"…\"; gate; push" deny-e \
    'git commit -q -m "fix \"q\" x"; ruby scripts/docs_band.rb >/dev/null 2>&1; echo "B=$?"; git push origin main'
  t "E: Q1 bash -o pipefail -c '… | tail && push'" deny-e \
    "bash -o pipefail -c 'cd /x && ruby scripts/docs_check.rb 2>&1 | tail -1 && git push origin main'"
  t "E: H1 escaped backtick is text, not code" silent \
    $'git add f && printf \'%s\\n\' "fix: \\`band\\` зелений; ruby scripts/docs_band.rb 0 FAIL" | git commit -F -'
  pad8k=$(head -c 8300 /dev/zero | tr '\0' x)
  t "E: past 8 KB the call is split unmasked" deny-e \
    $'# don\'t panic\n# '"$pad8k"$'\nruby scripts/docs_band.rb >/dev/null 2>&1; echo \'B\'\ngit push origin main'
  # [OPS.45] A warning QUEUED before a BLOCK must neither silence the deny nor be spent by
  # it. The first case is the kill-case of print-and-exit inside warn() (it gave `warn`);
  # the pair after it, in one session, kills setting the marker before the flush (the
  # second call then went silent). D and I are pinned behind a warning in their own blocks.
  t "OPS.45: fresh session — tail-truncated gate; push → E" deny-e \
    'bin/rspec spec/foo_spec.rb 2>&1 | tail -5; git push origin main'
  T_SID="selftest-$$-ops45"
  t "OPS.45: same session, the deny first…" deny-e \
    'bin/rspec spec/foo_spec.rb 2>&1 | tail -5; git push origin main'
  t "OPS.45: …did not spend A's warning" warn \
    'bin/rspec spec/foo_spec.rb 2>&1 | tail -5'
  unset T_SID
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

  # ── short SHA to `gh run list --commit` · both arms ──
  # The negatives carry the two shapes a loose anchor would deny: the house fix
  # itself (a `$(git rev-parse …)` substitution) and a `-c <hex>` that belongs to
  # a NEIGHBOURING statement, where `-c` is not gh's flag at all.
  t "gh: short SHA to --commit (09-14 relapse)" deny \
    "gh run list --commit 9434258f --limit 20 --json workflowName,status,conclusion --jq '.[] | .workflowName'"
  t "gh: short SHA in the --commit= form" deny \
    'gh run list --commit=23f2e3f6 --limit 5'
  t "gh: full 40-hex SHA stays silent" silent \
    'gh run list --commit 23f2e3f636ad7c5aa9b55e43bd134a7236f02f86 --limit 5'
  t "gh: rev-parse substitution stays silent" silent \
    'gh run list --commit "$(git rev-parse 9434258f)" --limit 5'
  t "gh: -c <hex> in a NEIGHBOUR statement stays silent" silent \
    'gh run list --branch main --limit 5; git log -c 9434258f'

  t "smoke: gate into tail warns (rule A)" warn \
    'bin/rspec spec/foo_spec.rb 2>&1 | tail -5'
  t "smoke: \$? after pipe warns (rule B)" warn \
    'ruby x.rb | tail -1; echo "EXIT=$?"'

  # ── OPS.39 · the exception must not swallow its own defect ──
  # Uppercase PIPESTATUS is empty in zsh, so it is NOT "already reading the status";
  # lowercase $pipestatus IS, and must still silence the rule. Both arms, or the fix
  # is untestable: a case that passes before and after the patch pins nothing.
  t "OPS.39: uppercase PIPESTATUS no longer silences rule A" warn \
    'bin/rspec spec/foo_spec.rb 2>&1 | tail -5; echo "EXIT=${PIPESTATUS[0]}"'
  t "OPS.39: zsh \$pipestatus (the correct idiom) stays silent" silent \
    'bin/rspec spec/foo_spec.rb 2>&1 | tail -5; echo "EXIT=$pipestatus[1]"'

  # ── rule G · both arms ──
  # The negative arm is the load-bearing one: `pgrep -x` and a pgrep OUTSIDE any
  # loop are the two idioms this must never touch, and a detector anchored on the
  # word `pgrep` alone would swallow both.
  t "G: until-loop on pgrep -f warns" warn \
    $'until ! pgrep -f \'SilkenCad.*fea\' >/dev/null; do sleep 20; done; echo DONE'
  t "G: while-loop on pgrep -f warns" warn \
    'while pgrep -f "docs_band.rb" >/dev/null; do sleep 5; done'
  t "G: pgrep -x in a loop stays silent" silent \
    'until ! pgrep -x dotnet >/dev/null; do sleep 5; done'
  t "G: bare pgrep -f outside a loop stays silent" silent \
    'pgrep -fl "SilkenCad" | head -3'
  t "G: artifact-wait (the sanctioned form) stays silent" silent \
    'until grep -q "ALL DONE" /tmp/run.log; do sleep 10; done'

  # ── rule D · all four arms ──
  # This detector reads git STATE, not the command text, so a case built from a
  # string alone is vacuous: on a clean tree the deny arm is unreachable and the
  # battery would be green for the wrong reason. The fixture therefore makes a
  # genuinely dirty tracked path — `git add -N` registers intent-to-add, so
  # `git diff --numstat` reports lines against an empty index entry, and no
  # commit is involved. `trap` guarantees removal even if a case aborts.
  dfix=".bashguard_selftest_dirty.tmp"
  if git rev-parse --git-dir >/dev/null 2>&1; then
    trap 'git rm --cached -q "$dfix" 2>/dev/null; rm -f "$dfix"; rm -rf "$TMPDIR"' EXIT
    printf 'a\nb\n' > "$dfix"
    git add -N "$dfix" 2>/dev/null
    t "D: checkout of a DIRTY tracked file denies" deny \
      "git checkout $dfix"
    t "D: declared intent (token) stays silent" silent \
      "git checkout $dfix  # discard-dirty"
    t "D: backup taken in the SAME call stays silent" silent \
      "cp $dfix /tmp/f.bak && git checkout $dfix"
    # 2026-09-29: the form that fooled the co-occurrence check — `cp` of OTHER
    # files plus the dirty path named twice — and a `cp` that restores INTO it.
    t "D: cp of other files + the path named twice still denies" deny \
      "cp /tmp/a.bak other.rb; probe x $dfix; git checkout -q -- $dfix"
    t "D: a cp INTO the dirty path is a restore, not a backup" deny \
      "cp /tmp/f.bak $dfix && git checkout $dfix"
    t "D: behind a queued A warning still denies [OPS.45]" deny \
      "bin/rspec spec/x_spec.rb 2>&1 | tail -3; git checkout $dfix"
    git rm --cached -q "$dfix" 2>/dev/null
    rm -f "$dfix"
    trap 'rm -rf "$TMPDIR"' EXIT  # back to the battery's own trap, not to none
    # The false-positive arm: a path with NO uncommitted lines must never deny,
    # or every legitimate revert becomes blocked work.
    t "D: checkout of a CLEAN file stays silent" silent \
      "git checkout README.md"
  fi

  # ── H · git add of a directory while a compute cache is dirty ──────────────
  # Both arms, mutation-verified: remove the `(tools|docs|\.|:/)` alternation and
  # the three positives go silent; remove the dirty-check and the clean-tree
  # negative warns. The three positives are the three REAL relapse forms of
  # 2026-10-04 — including the `--` one, which read as precision and is not.
  # ⛔ NOT in a subshell: `( … t … )` drops the case's n/fails increments, so a failing
  # H case printed ✗ while the battery still said OK — measured 2026-10-04 by the
  # adversary of OPS.40 (six cases uncounted). The variable is exported at the top.
  BASHGUARD_CACHE_DIRTY=" M tools/in_silico/cache/dft/x.json"
  t "H: git add -A sweeps a warm cache" warn "git add -A && git commit -s -m x"
  t "H: narrowed to directories is NOT a fix" warn "git add -A docs tools"
  t "H: the \`--\` form is not a fix either" warn "git add -- docs tools NOTICE"
  t "H: explicit FILE paths stay silent" silent \
    "git add -- docs/00_07_Action_Plan_Tracker.md tools/in_silico/scripts/80_x.py"
  t "H: add -p is interactive, not a sweep" silent "git add -p tools"
  BASHGUARD_CACHE_DIRTY=clean
  t "H: a CLEAN cache tree makes the sweep harmless" silent "git add -A"

  # ── I · the archive act through a script [OPS.41] · both arms ──
  # The positives are corpus forms: a row after an escaped `\n` inside a Python
  # literal (how this very rule's item was archived) and a row at line start. The
  # negatives are the shapes the discriminator must leave alone: a read-only grep of
  # a row, a tracker write with no row, a row written into ANOTHER doc, and a table
  # row whose first cell is not a tracker ID. Fixture IDs carry the `FIXT` prefix —
  # not a tracker family, so the phantom-ID gate leaves them alone (ssot_guard_hint.sh
  # says why in its own battery).
  t "I: row after escaped \\n in a script writing 00_07" warn-i \
    $'python3 - <<\'PY\'\np=\'docs/00_07_Action_Plan_Tracker.md\'; s=open(p,encoding=\'utf-8\').read()\nrow=(\'\\n| FIXT.9 | **закрито** | `00_06 §3` |\')\nopen(p,\'w\',encoding=\'utf-8\').write(s+row)\nPY'
  t "I: row at line start in a heredoc script" warn-i \
    $'ruby -e \'p="docs/00_07_Action_Plan_Tracker.md"; File.write(p, File.read(p) + ARGF.read)\' <<\'ROW\'\n| FIXT-9 | **закрито** | `05_05 §3` |\nROW'
  t "I: read-only grep of a row stays silent" silent \
    'grep -nF "| FIXT.3 | " docs/00_07_Action_Plan_Tracker.md'
  t "I: tracker write with no row stays silent" silent \
    $'python3 - <<\'PY\'\np=\'docs/00_07_Action_Plan_Tracker.md\'; s=open(p).read()\nopen(p,\'w\').write(s.replace(\'- [ ] a\',\'- [ ] b\'))\nPY'
  t "I: a row written into ANOTHER doc stays silent" silent \
    $'python3 - <<\'PY\'\nopen(\'docs/02_05_x.md\',\'w\').write(\'| FIXT.9 | x |\')\nPY'
  t "I: a non-ID first cell stays silent" silent \
    $'python3 - <<\'PY\'\np=\'docs/00_07_Action_Plan_Tracker.md\'\nopen(p,\'w\').write(\'| SWD | пади | так |\')\nPY'
  t "I: the archive hint survives a queued A warning [OPS.45]" warn-i \
    $'bin/rspec spec/x_spec.rb 2>&1 | tail -1; python3 - <<\'PY\'\np=\'docs/00_07_Action_Plan_Tracker.md\'; s=open(p,encoding=\'utf-8\').read()\nopen(p,\'w\',encoding=\'utf-8\').write(s+\'\\n| FIXT.9 | **закрито** | `00_06 §3` |\')\nPY'

  if (( fails > 0 )); then
    echo "bash_verify_guard --selftest: ${fails}/${n} FAILED"
    exit 1
  fi
  echo "bash_verify_guard --selftest: OK (${n} cases — rules D, E, F, H and I all arms + smoke over A/B/C/backtick/rg)"
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

# ── BLOCK · a SHORT sha handed to `gh run list --commit` ─────────────────────
# `--commit` filters on the FULL 40-character SHA. A short one matches nothing,
# and gh answers with an EMPTY list and exit 0 — verified live 2026-09-14:
# `--commit 23f2e3f6` gave 0 runs, the same commit's full SHA gave 5. So the
# output has no symptom: an empty list reads as «CI has not started yet», and in
# a wait-until-every-run-completed loop it reads as «all done» at once.
#
# Measured 2026-09-14 over 177 session transcripts: 23 distinct calls hand
# `--commit` a short hex literal (22 of them eight characters) against 12 that
# pass a full SHA or a substitution — the short form is the HABIT, not a slip.
# Memory recorded the lesson 2026-08-17 (the empty set read as «CI did not see
# the push») and it relapsed 2026-09-14 in a CI waiter that exited over the
# empty set: a journal does not fire at the moment of typing, this does.
#
# A BLOCK for the rg reason above: the failure is in the OUTPUT the caller is
# about to believe, never in the exit code. Segment-scoped (`[^;&|]*`), so a
# `-c <hex>` in a NEIGHBOURING statement (`git log -c …`) stays silent, and a
# 40-hex literal or a `$(…)` / `"$VAR"` value can never match.
if printf '%s' "$cmd" | grep -qE "(^|[;&|(])[[:space:]]*gh[[:space:]]+run[[:space:]]+list([[:space:]][^;&|]*)?[[:space:]](--commit|-c)([[:space:]]+|=)[\"']?[0-9a-f]{4,39}([\"'[:space:];&|)]|\$)"; then
  jq -nc --arg r '`gh run list --commit` filters on the FULL 40-character SHA: a short SHA matches NOTHING, and gh returns an empty list with exit 0 (verified here: `--commit 23f2e3f6` gave 0 runs, the full SHA of the same commit gave 5). The empty list has no symptom — it reads as «CI has not started», and a wait-until-all-completed loop ends at once as «all done». Pass the full SHA: --commit "$(git rev-parse <sha>)".' \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
fi

# ── WARN · once per session per class ────────────────────────────────────────
# The marker idiom is borrowed from ssot_guard_hint.sh for the reason stated
# there: a noisy advisory is a disabled gate. It takes rule A from 1,564 firings
# a month to ≤158, and rule B from 393 to ≤133.
# 🔑 [OPS.45] DEFERRED: warn() queues and returns; the flush at the END of the file
# prints the queue and only then sets the markers. Every BLOCK below therefore
# decides first, and its deny discards the queue — markers included, so a warning
# the reader never saw is not spent. ⛔ Never print-and-exit inside warn(): the
# first call of a session that trips A/B/F (or C's lanterns) then never reaches D,
# C or E — measured 2026-10-24 on recorded commit/push calls, 11 got a warning
# where E's deny existed (00_07 OPS.45).
pending_ctx=""; pending_marks=""  # strings, not arrays: bash 3.2 + `set -u` dies on an empty "${a[@]}"
warn() {
  local class=$1 text=$2 marker
  marker="${TMPDIR:-/tmp}/claude-bashguard-${session}-${class}"
  [[ -f "$marker" || "$pending_marks" == *"$marker"* ]] && return 0
  pending_ctx+="${pending_ctx:+$'\n\n'}${text}"
  pending_marks+="${marker}"$'\n'
}

# The verdict-emitting gate vocabulary — shared by rule A (a gate truncated
# into head/tail) and rule E (a gate laundered past git commit/push), so it is
# defined OUTSIDE the pipestatus/pipefail conditional below: a command that merely
# mentions `pipefail` skips A/B, and rule E must still see the list.
# Report generators are deliberately absent: stan_audit.rb and mem_find.rb have
# no `exit 1` path at all, so slicing them is querying, not truncating a verdict.
gate='(bin/rspec|bundle exec rspec|bin/rubocop|bundle exec rubocop|bin/brakeman|bin/bundler-audit|bin/ci|make -C firmware/test|forge (test|build|coverage)|ruff check|pytest|bin/rails (docs:|tracker:|gaia:|zeitwerk:|spec)|rake (docs:|tracker:))'

# Already reading the pipeline's real status → silent. 222 calls do this, and
# three of the first five false positives measured were exactly this case.
# 🔴 `PIPESTATUS` (UPPERCASE) sat in this list until 2026-09-21 and never belonged:
# it is a bash-ism that expands to EMPTY in zsh — i.e. the very defect rules A and B
# exist to catch — so the exception was reading the DEFECT as proof of correctness.
# Shape: guard-craft #102, an exception argued per-MEMBER and applied per-CONTAINER.
# Perimeter measured BEFORE flipping it (00_07 OPS.39): 6 uppercase uses across
# 51,117 calls / 181 sessions, and all six were the token as a SEARCH STRING rather
# than as a variable — so this narrowing costs ~0 live firings. ⛔ Do not re-add it:
# both warn texts below already tell the reader the uppercase form expands to empty.
if ! printf '%s' "$cmd" | grep -qE 'pipestatus|pipefail'; then

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
      # Declared exit 2: that same path is the SOURCE of a `cp` in this very call —
      # a backup of the dirty state, so the loss is reversible. 🔴 Co-occurrence is
      # NOT that (2026-09-29): a mutation-probe call restored OTHER files with
      # `cp <backup> <file>` and named the dirty path twice as a probe argument;
      # «a cp somewhere + the path twice» went silent, and the checkout ate 51
      # uncommitted lines. A `cp` INTO the path is a restore, never a backup.
      p_re=$(printf '%s' "$p" | sed -E 's/[][\.^$*+?(){}|\\/]/\\&/g')
      if printf '%s' "$cmd" | tr ';&|' '\n\n\n' |
           grep -qE "^[[:space:]]*cp([[:space:]]+-[[:alnum:]]+)*[[:space:]]+[\"']?${p_re}[\"']?([[:space:]]|$)"; then
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
# class (2 measured); an unterminated heredoc swallows the rest of the call, and
# only the first heredoc opener on a line is honoured.
#
# 🔑 [OPS.40] TWO vocabularies, paired by SUBJECT — a verdict gates only the git
# step of the tree it judged: repo gates ↔ a git step on the repo, and
# `memory_gate.sh --audit` ↔ a git step on the memory corpus. The subject of a git
# step is its `-C <dir>`, else the last `cd` of the call; a dir is the corpus when
# it carries `/memory` or is a variable the same call assigns such a path (shell
# state does not survive between calls, so an unassigned `$M` stays UNKNOWN and
# pairs with neither). A memory audit before a REPO commit is not this class: the
# audit reads repo paths, but what it judges is the corpus, and a repo commit does
# not repair it. And heredoc BODIES are cut, not everything after the first
# opener: the call goes on after the terminator, and that is where it laundered.
# 🔴 Bought twice on 2026-10-04. The first fix was measured with this block's OWN
# classifier, which dropped all text below a heredoc — so the measurement shared
# the blindness it measured (guard-craft #12): it saw 5 flips, every one over a
# GREEN audit, while the 2026-09-23 incident itself (`--audit; echo; git -C …
# commit` on the line after a `python3 <<'PY'` body) stayed silent, as did each
# `cd $M && git commit` — the MAJORITY form of memory commits, not a dying one.
# The adversary caught it the same day. Re-measured over 2,474 recorded
# commit/push calls (145 transcripts, 121 sessions, 09-04 → 10-04): the fix adds
# 42 denies — 16 memory, 26 repo laundered below a heredoc — to the 64 the block
# already gave, with no regression, and every one of the 42 discards a verdict
# before a commit or push of the same tree.
#
# 🔑 [OPS.43] A git step also starts a PIPE ELEMENT, with git's global flags allowed.
# Measured 2026-10-23 on a live call: `gate; echo; git add f && printf … | git commit -F -`
# passed while the same call with `-F <file>` denied — the link starts with printf. The
# split and the git-step search now run on a MASKED copy: a quoted token whose content
# holds `;`, `&`, `|` or a newline is blanked (`'…'`, `$'…'`; `"…"` only without an
# UNESCAPED `$(` or backtick — there the code runs), so `rg 'git add|git commit'` names no
# git step and a `;` inside a message splits nothing; tokens without those stay whole, so
# `git -C "$M"` still names its tree. The mask pairs quotes by regex, not as the shell does,
# so a STRAY quote (an apostrophe in a `#` comment, a heredoc body the cutter missed, quotes
# nested in `"$( )"`) pairs with the next quote anywhere: a blanked token that holds a
# separator and then `git … commit|push` is therefore kept as code (fail-closed), and the
# `-m "…"` strip reads `\"` as escaped. sed/tr only; BSD sed is quadratic on dense `\"`, so
# past 8 KB the mask is skipped and the call is split unmasked (the 2,358 recorded
# commit/push calls of 2026-10-24 all sit under 7.6 KB). ⛔ Not a hand-written shell lexer
# (built 2026-10-24 and withdrawn the same day — it lost the incident class itself and went
# quadratic) and not a printf/echo strip by WORD (lost real denies).
# Ceilings, declared, not cured — a laundered call that passes: an apostrophe in a `#`
# comment BEFORE the gate pairs with a later quote and blanks the gate itself; the
# heredoc cutter takes `<<WORD` anywhere on a line as an opener (`$((1<<N))`, `<<<`, a
# `<<` operator, quoted text) and cuts the lines after it; a `-c` body behind other flags
# (`bash -e -c`, `-c --`, `--norc -c`, `-lc`, `zsh -f -c`) or under `ssh host '…'` is text
# unless it holds a git step after a separator, and `bash <<'SH'` bodies are cut;
# `| xargs git`, `env`/`VAR=x`/`command`/`time`/`/usr/bin/git` before git (ZERO real calls
# in 3,100 recorded commit/push calls); `if … then git`, `gate & git`, `(cd $M && git …)`;
# `gate || true && git commit` (`||` is a plain link separator); `for … do gate; done;
# git push`; `;` inside `$( )` splits like any other. A clean call that DENIES: a
# `\`-continued `&&` chain, `find -exec … \;`, a `;` inside a quoted message within a
# `-c`/`eval` body (read as code).
rgit='git(([[:space:]]+-[Cc][[:space:]]+[^[:space:]]+)|([[:space:]]+-[Pp])|([[:space:]]+--(git-dir|work-tree)[[:space:]]+[^[:space:]]+)|([[:space:]]+--[a-z-]+(=[^[:space:]]+)?))*[[:space:]]+(commit|push)'
if printf '%s' "$cmd" | grep -qE "${rgit}\b"; then
  # Heredoc BODIES are cut, the lines after each terminator are KEPT [OPS.40 fix-forward]:
  # the body is where a commit message names a gate, but the call goes on after it.
  ecmd=$(printf '%s\n' "$cmd" | awk -v q="'" '
    skip { t = $0; sub(/^[ \t]+/, "", t); sub(/[ \t]+$/, "", t); if (t == term) skip = 0; next }
    { print
      if (match($0, "<<-?~?[ \t]*[\"" q "]?[A-Za-z_][A-Za-z0-9_]*")) {
        w = substr($0, RSTART, RLENGTH); sub("^<<-?~?[ \t]*[\"" q "]?", "", w); term = w; skip = 1 } }')
  ecmd=$(printf '%s' "$ecmd" | sed -E "s/-m[[:space:]]+\"([^\"\\\\]|\\\\.)*\"/-m MSG/g; s/-m[[:space:]]+'[^']*'/-m MSG/g")
  [[ -z "$ecmd" ]] && ecmd=$cmd  # [OPS.43] awk or sed failed: judge the raw call, never nothing
  # [OPS.43] The masked copy: every quoted token wrapped (\001…\002, leftmost first, so a
  # quote inside another kind never opens one; `\\.` keeps an escaped quote out), the body
  # of `bash|sh|zsh -c` / `eval` and a "…" holding an unescaped `$(`/backtick unwrapped — both
  # RUN, as the unmasked split always read them — and so is a token holding a separator then
  # `git … commit|push` (a stray quote may have opened it); the rest blanked when a separator
  # sits inside; newlines ride
  # as \003 so a token can span them. Empty output (sed failed) → the unmasked call.
  read -r -d '' mask_sed <<'SED'
s/(\\.|\$'([^'\\]|\\.)*'|'[^']*'|"([^"\\]|\\.)*")/<SO>\1<SC>/g
s/((bash|sh|zsh)[[:space:]]+-[a-z]*c[[:space:]]+|eval[[:space:]]+)<SO>([^<SC>]*)<SC>/\1\3/g
s/<SO>("([^<SC>\\]|\\.)*(\$\(|`)[^<SC>]*")<SC>/\1/g
s/<SO>([^<SC>]*[;&<NL>][[:space:]]*git[[:space:]][^<SC>;&|<NL>]*(commit|push)[^<SC>]*)<SC>/\1/g
s/<SO>\$'[^<SC>]*[;&|<NL>][^<SC>]*'<SC>/$'_'/g
s/<SO>'[^<SC>]*[;&|<NL>][^<SC>]*'<SC>/'_'/g
s/<SO>"[^<SC>]*[;&|<NL>][^<SC>]*"<SC>/"_"/g
s/[<SO><SC>]//g
SED
  mask_sed=${mask_sed//<SO>/$'\001'}; mask_sed=${mask_sed//<SC>/$'\002'}; mask_sed=${mask_sed//<NL>/$'\003'}
  mcmd=$ecmd  # past 8 KB the mask is skipped: BSD sed is quadratic on dense \" and the hook has 5 s
  if (( ${#ecmd} <= 8192 )); then
    mcmd=$(printf '%s' "$ecmd" | LC_ALL=C tr '\n' '\003' | LC_ALL=C sed -E "$mask_sed" | LC_ALL=C tr '\003' '\n')
  fi
  [[ -z "$mcmd" ]] && mcmd=$ecmd
  egate="((env[[:space:]]+[^[:space:]]+[[:space:]]+)?([A-Z_]+=[^[:space:]]+[[:space:]]+)*)?(${gate}|ruby[[:space:]]+scripts/(docs_band|docs_check|model_doc_sync)\.rb)"
  mgate='(([A-Z_]+=[^[:space:]]+[[:space:]]+)*)(bash[[:space:]]+)?[^[:space:]]*memory_gate\.sh[[:space:]]+--audit'
  # The SUBJECT of a git step is the tree it writes: `-C <dir>`, else the last `cd` of the
  # call. A dir is the memory corpus when it carries `/memory` or is a variable this call
  # assigns such a path (`M=…/memory`) — the corpus is never written any other way here.
  mvars=$(printf '%s' "$ecmd" | grep -oE "(^|[;&|[:space:]])[A-Za-z_][A-Za-z0-9_]*=[\"']?[^[:space:];&|\"']*/memory([\"'/[:space:];&|]|$)" \
            | sed -E 's/^[;&|[:space:]]*//; s/=.*//' | sort -u | paste -sd'|' -)
  is_mem() { [[ "$1" == */memory* ]] || { [[ -n "$mvars" ]] && printf '%s' "$1" | grep -qE "^[\"']?\\\$\{?(${mvars})\}?[\"']?$"; }; }
  # launder <gate-re> <subject: repo|mem> → prints the laundered form, or nothing
  launder() {
    local g=$1 want=$2 verdict="" gate_seen="" st lk links st_gate st_git st_piped cwdm=0 tgt mem el pl x
    local -a w
    while IFS= read -r st; do
      links=${st//&&/$'\n'}
      links=${links//||/$'\n'}
      st_gate=""; st_git=""; st_piped=""
      while IFS= read -r lk; do
        if printf '%s' "$lk" | grep -qE "^[[:space:]]*${g}"; then
          st_gate=1
          printf '%s' "$lk" | grep -q '|' && st_piped=1
        fi
        if [[ "$lk" =~ ^[[:space:]]*cd[[:space:]]+([^[:space:]]+) ]]; then
          is_mem "${BASH_REMATCH[1]}" && cwdm=1 || cwdm=0
        fi
        pl=${lk//|&/|}
        while IFS= read -r el; do  # [OPS.43] the link's start and every pipe element
          [[ "$el" =~ $re_gitstep ]] || continue
          tgt=""; mem=""
          read -ra w <<< "${BASH_REMATCH[0]}"
          for ((x = 1; x < ${#w[@]}; x++)); do
            case ${w[x]} in
              -C|--git-dir|--work-tree) tgt=${w[x+1]:-} ;;
              --git-dir=*|--work-tree=*) tgt=${w[x]#*=} ;;
            esac
          done
          if [[ -n "$tgt" ]]; then
            if is_mem "$tgt"; then mem=mem; elif [[ "$tgt" == "." || "$tgt" == "./" ]]; then mem=repo; fi
          else
            (( cwdm )) && mem=mem || mem=repo
          fi
          [[ "$mem" == "$want" ]] && st_git=1
        done <<< "${pl//|/$'\n'}"
      done <<< "$links"
      if [[ -n "$st_git" && -z "$st_gate" && -n "$gate_seen" && "$verdict" != "piped" ]]; then verdict="semicolon"; fi
      if [[ -n "$st_gate" && -n "$st_git" && -n "$st_piped" ]]; then verdict="piped"; fi
      [[ -n "$st_gate" ]] && gate_seen=1
    done < <(printf '%s\n' "$mcmd" | tr ';' '\n')
    printf '%s' "$verdict"
  }
  re_gitstep="^[[:space:]]*${rgit}([[:space:]]|\$)"
  verdict=""; pair="a repo gate before a repo git step"
  printf '%s' "$mcmd" | grep -qE "$egate" && verdict=$(launder "$egate" repo)
  if [[ -z "$verdict" ]] && printf '%s' "$mcmd" | grep -qE "$mgate"; then
    verdict=$(launder "$mgate" mem); pair="memory_gate.sh --audit before a commit/push of the memory corpus"
  fi
  if [[ -n "$verdict" ]]; then
    jq -nc --arg r "A verdict-emitting gate and git commit/push share this call (${pair}), but the verdict does NOT gate the git step (${verdict} form): they are joined by \`;\`/newline, or the gate is piped so tail/grep's exit replaces its own. The verdict arrives only AFTER the whole call has run — reading it then is a report about a consequence, not verification, and this exact shape pushed a red docs band to main twice (2026-08-16, 2026-08-20) and committed the memory corpus over a red audit (2026-09-23). Run the gate in its OWN call and read the verdict first; or use the sanctioned single-call form — every step joined by a clean unpiped \`&&\`, so a red gate mechanically STOPS the chain. [OPS.31 · OPS.40 · OPS.43]" \
      '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
    exit 0
  fi
fi

# ── G · WARN · a wait-LOOP polling `pgrep -f <literal>` (25 in 42,305) ───────
# The loop text itself carries the pattern, so ANY second process whose command
# line also carries it keeps every one of them alive forever — and the commonest
# such process is another copy of the same waiter. The Bash tool's own detached
# shells are the supply: they linger past the call that made them, and `ps` shows
# their full script, so three stacked waiters on `SilkenCad.*fea` held a QUEUED
# job at 0% CPU for ten minutes on 2026-09-18 while every poll read "RUNNING".
#
# ⚠️ WARN, not block, and the reason is a measurement that OVERTURNED the rule as
# memory had written it. Memory said the loop "matches its OWN command line" and
# therefore never exits; measured here, a LONE loop exits correctly — macOS pgrep
# does not match the ancestor shell (probe: a marker inside `bash -c` is invisible
# to a pgrep run from inside that same `bash -c`, and plainly visible to one run
# from outside). So the idiom is sound alone and fails only in COMPANY, which is
# exactly why it kept passing and kept relapsing: four documented relapses, the
# last of them this block's own author.
#
# `pgrep -x` (34 calls) is the safe sibling and stays silent: it matches the
# executable NAME, which a shell script's text is not.
if printf '%s' "$cmd" | grep -qE '(^|[;&|(]|[[:space:]])(until|while)[[:space:]]' &&
   printf '%s' "$cmd" | grep -qE '\bp(grep|kill)[[:space:]]+-[a-zA-Z]*f[a-zA-Z]*[[:space:]]+["'"'"']?[^"'"'"'$[:space:]]'; then
  warn pgrep-wait-loop '[bash-guard] A wait-loop polls `pgrep -f <literal>`. The loop'"'"'s own command line contains that literal, so a SECOND process carrying it — most often another copy of this waiter, and the detached shells of earlier Bash calls linger — keeps them all alive forever, while each poll reads as "still running". Wait on the ARTIFACT instead (`until grep -q "<verdict>" out.log; do sleep N; done`), or match the executable name with `pgrep -x`. Measured: a lone loop DOES exit; the failure needs company. (Fires once per session.)'
fi

# ── H · WARN · `git add` of a DIRECTORY that contains a compute cache ─────────
# Three relapses in ONE day (2026-10-04) on the same defect: a still-warm DFT
# cache swept into a commit by `git add -A`, then by `git add -A docs tools`, then
# by `git add -- docs tools NOTICE`. The narrowing LOOKED like the fix each time,
# and the third form even carries the `--` separator that reads as precision.
#
# Why no rule in a skill can hold this: the carrier has to fire at the moment of
# `git add`, and the skill that states the rule (`in-silico` §When Modifying #21) is not loaded
# then. The relapse was never about knowing the rule — its home was patched one
# hour before relapse #2. Class: memory `feedback_rule_needs_a_carrier`.
#
# Perimeter: fires only when a DIRECTORY argument (or -A/-u with no pathspec)
# could reach a cache tree, and only while such a tree is actually dirty — a clean
# tree makes the sweep harmless, and this is the half that keeps the rule quiet.
# Explicit file paths are the sanctioned form and stay silent by construction.
# ⚠️ ANCHORED to the start of a statement, which is rule A's measured lesson applied
# here: the un-anchored first draft of this rule fired on a `python3` heredoc whose
# BODY contained the string `git add -A` (it was writing this very battery), and on
# two of rule E's own negative cases. A mention is not an invocation.
gitadd='(^|[;&]|&&|\|\||\|)[[:space:]]*git[[:space:]]+add[[:space:]]'
if printf '%s' "$cmd" | grep -qE "$gitadd" &&
   printf '%s' "$cmd" | grep -qvE "${gitadd}+(-N|--intent-to-add|-p|--patch)\b"; then
  # a pathspec that is a plain directory, or a blanket -A / -u with none
  if printf '%s' "$cmd" | grep -qE '\bgit[[:space:]]+add[[:space:]]+(-[AuaE]+[[:space:]]*)*(--[[:space:]]+)?([^[:space:]-][^[:space:]]*[[:space:]]+)*(tools|docs|\.|:/)([[:space:]]|$)' ||
     printf '%s' "$cmd" | grep -qE '\bgit[[:space:]]+add[[:space:]]+(-A|--all|-u|--update)([[:space:]]|$)'; then
    # ⚠️ The dirty-check is a RUNTIME condition, so a battery case built on the real
    # working tree would pass or fail depending on what is mid-computation — a flaky
    # pin, i.e. no pin. `BASHGUARD_CACHE_DIRTY` lets --selftest state the condition
    # explicitly and pin BOTH directions (dirty→warn, clean→silent) deterministically.
    cache_dirty="${BASHGUARD_CACHE_DIRTY:-$(git status --porcelain -- tools/in_silico/cache 2>/dev/null)}"
    [[ "$cache_dirty" == "clean" ]] && cache_dirty=""
    if [[ -n "$cache_dirty" ]]; then
      warn git-add-warm-cache '[bash-guard] `git add` with a DIRECTORY pathspec (or -A/-u) while `tools/in_silico/cache/` is dirty. A still-warm compute cache gets swept into the commit, and the narrower directory form is NOT the fix — measured three times in one day, including with `--`. Name the files explicitly: `git add -- path/one path/two`. Check first: `git status --porcelain -- tools/in_silico/cache`. (Fires once per session.)'
    fi
  fi
fi

# ── I · WARN per ACT · a script writes an ARCHIVE ROW into `00_07` [OPS.41] ─────
# The script arm of the archive-act carrier; the Edit/Write arm and the hint text
# live in ssot_guard_hint.sh (`--archive-hint`), so the wording has one home. This
# arm is not the minor one: measured 2026-10-04 over 40,171 recorded calls, 2,392
# wrote `00_07` by script — the hook on Edit/Write never sees them. 36 of those
# carried a row literal whose first cell is a tracker ID — a shape that exists ONLY
# under `## 🗄️` — and the spot-checked ones fell on the days those IDs were archived
# or cemented. Keyed per (session, ID set), NOT once per session: the event to catch
# is the act, and a session-keyed carrier is exactly what failed here (guard-craft
# #104). The row literal may follow a quote or an escaped `\n` inside a script.
# ⚠️ Ceilings, named: a script that only CUTS a `#### ID` block, with no row literal,
# is invisible — what a script removes is runtime, not text; a row used as an ANCHOR
# is listed beside the archived one (the hint says so); and a script that EDITS an
# existing archive row fires too — its text cannot tell an insert from an edit
# (measured on this rule's first day, on its author's own fix-forward).
if printf '%s' "$cmd" | grep -qF '00_07_Action_Plan_Tracker' &&
   printf '%s' "$cmd" | grep -qE "File\.write|\.write\(|write_text|open\([^)]*['\"]w['\"]|sed -i|perl -i|>[[:space:]]*docs/00_07"; then
  arch_ids=$(printf '%s\n' "$cmd" \
    | grep -oE "(^|[\"'(]|\\\\n)[[:space:]]*\| [A-Z][A-Za-z0-9]*(-[A-Za-z0-9]+)*(\.[0-9][0-9A-Za-z.]*|-[0-9]+) \| " \
    | grep -oE '\| [^ ]+ \| $' | sed -E 's/^\| ([^ ]+) \| $/\1/' | LC_ALL=C sort -u | tr '\n' ' ')
  if [[ -n "${arch_ids// /}" ]]; then
    amark="${TMPDIR:-/tmp}/claude-bashguard-${session}-archive-$(printf '%s' "$arch_ids" | tr -c 'A-Za-z0-9.-' '_')"
    if [[ ! -f "$amark" && "$pending_marks" != *"$amark"* ]]; then
      actx=$(bash "$(dirname "$0")/ssot_guard_hint.sh" --archive-hint "$arch_ids" 2>/dev/null)
      if [[ -n "$actx" ]]; then
        pending_ctx+="${pending_ctx:+$'\n\n'}${actx}"
        pending_marks+="${amark}"$'\n'
      fi
    fi
  fi
fi

# ── flush · reached only when no BLOCK denied [OPS.45] ───────────────────────
# The markers are set HERE, after the text is out, so a deny earlier in the file
# never spends a warning the reader did not see. All queued warnings share one
# additionalContext: the output has to be a single JSON object.
if [[ -n "$pending_ctx" ]]; then
  while IFS= read -r m; do [[ -n "$m" ]] && : > "$m"; done <<< "$pending_marks"
  jq -nc --arg ctx "$pending_ctx" '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$ctx}}'
fi
exit 0
