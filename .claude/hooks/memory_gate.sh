#!/usr/bin/env bash
# Growth gate for the persistent memory corpus.
#
# The corpus lives OUTSIDE the git repo, so no CI can see it. The only
# enforcement point left is the moment of writing — and that is exactly where
# every previous rule failed, because its carrier stood somewhere else (a skill
# that fires on "clean up", a prompt read during housekeeping).
#
# Since 2026-08-08 the corpus DOES carry its own local git (memory-dir, no
# remote, `memory_git_commit.sh` commits every write), so `git revert` exists
# here now — but that changes the curator's proof bar, NOT this gate's job.
# Revert only ever helps a loss somebody NOTICED; the losses this file is built
# to catch are the silent ones, and for those the write is still the last moment
# anyone is looking.
#
# MANY stances, one engine. The roster is the `case "${1:-}"` block near the bottom
# — READ IT THERE, never from a list here: this header said "three stances" while the
# block carried seven, i.e. it described its own contents and rotted, which is the
# very class this gate is written against. The load-bearing distinction is not which
# modes exist but WHY some sit outside `--audit`: a check whose live yield is a
# handful belongs in the battery; one whose yield runs to dozens is a worklist, and
# folding a worklist in makes EXIT 1 permanent — which trains the reader to skim the
# one stance that must stay loud. The no-argument stance is the PostToolUse hook.
#
# ⏱ TIME BUDGET — measured, not assumed (DOC-T.64, 2026-08-09, corpus 1.69 MB):
#   write stance (the hook)  6.4 s   against a 30 s `timeout` in .claude/settings.json
#   --audit                 15.5 s   (not a hook; no budget applies)
# The budget was 10 s, i.e. a 1.56× margin on a cost that grows monotonically with
# the corpus — and a hook timeout is FAIL-OPEN: the write proceeds, this gate simply
# never spoke, and nothing anywhere records that it didn't. Raised to 30 s (≈4.7×).
# Re-measure when the corpus grows by half again: `/usr/bin/time -p` on a fixture
# write. Sibling hooks are nowhere near their budgets (0.01–0.07 s against 5–10 s).
set -uo pipefail

MEM_DIR="${MEMORY_GATE_DIR:-/Users/oleksiilukin/.claude/projects/-Users-oleksiilukin-silken-net/memory}"
IDX="$MEM_DIR/MEMORY.md"
REPO="${MEMORY_GATE_REPO:-/Users/oleksiilukin/silken_net}"
SELF=${BASH_SOURCE[0]:-$0}

# --- Curated thresholds. Bumping one is a deliberate, git-visible decision. ---
# Ratchet, not an absolute cap: the index is already past the 24 kB working cap,
# so an absolute threshold would fire on every write and get muted within a day.
# "No worse than it already is" gives monotone downward pressure and zero noise.
# Bumped 2026-08-01 (24814 -> 25850) for THREE new class-homes landing in one
# pass: one_token_two_domains, silent_default, irreversibility_proof_bar. This is
# structural growth, not sprawl — each displaced a class that had been scattered
# as a side-note across 20-35 files. Deliberately NOT paid for by trimming other
# rows: the measured effect is that cutting the index accelerates growth of the
# CORPUS (fewer visible homes -> more new files), so evicting rows to fund new
# homes is the wrong lever.
#
# LOWERED 2026-08-03 (25850 -> 23773): that owed eviction was paid, by hub-inline
# and not by prose. Thirteen rows became two hub rows — the "вісь помилки" family
# (8 rows, 2397 B, now one row routing 9 files) and the §07 cluster (5 rows + a
# redundant header). Zero files deleted or merged, zero link lost. Two measured
# lessons are worth more than the number: (1) a hub's saving comes from HOOK
# THICKNESS, not from how tightly the family is read — the tightest co-read
# cluster left (Hardware/EBFC, lift 14.7) already runs 162 B/row and would have
# repaid ~490 B while costing the scan layer its live 🔄/🔴 state; (2) demoted
# files are carried by their inbound [[strings]], so the strings go in FIRST —
# the three newest homes had only 3-4 external ones and zero direct reads, and
# were strung up to 7-8 before losing their rows. Founder's working band is
# ~21-22 kB; this sits at 23.2 kB, and the remaining gap has no candidate that
# passes the "natural family, read together" test — closing it would mean
# demoting commit-time reflexes (lift 2.5), which is a worse trade than the gap.
# Bumped 2026-08-04 (23773 -> 23836, +63) for the tenth error-axis home,
# `feedback_self_attestation`. It did NOT earn its own row: it is inlined into the
# existing "вісь помилки" hub, so the +63 is one link inside a row that already
# routes nine files — the cheapest shape available and the one DOC-T.57 proved.
# Why it earns even that: the tracker had already named this class three times on
# three independent tracts (ARCH.78 alerts, FW.63 money, UI.10 screen) with two
# items still OPEN, while memory had no home for it at all — the class was being
# re-derived from scratch every session. Displacing a row to fund it was rejected:
# the remaining candidates are commit-time reflexes, and demoting those costs a
# trigger at the moment of action.
# Bumped 2026-08-09 (23836 -> 24033, +197) for `project_uwei_process_layer_cut`.
# It DID earn its own row, which the previous bump's candidate did not: the file
# carries a ratified founder VERDICT (the whole team-shaped process layer —
# Projects V2, Shape Up, Betting Table, academic semesters, R&D clusters as an
# org chart — removed under У-ВЕЙ). A verdict with no memory home is not merely
# re-derived, it is re-LITIGATED: the next session proposes rebuilding what was
# deliberately cut, and the founder pays to issue the same ruling twice. Funded
# rather than free: ~470 B was first reclaimed by compressing two descriptions
# (memory_sync_program, arch57) and the local-verify row, so the net cost of the
# new home is this +197, not its full width.
# Every threshold below is `${ENV:-default}` for ONE reason: --selftest builds a
# five-file fixture corpus, and a constant calibrated against the 1.2 MB live one
# fires on every fixture. The default stays in the file, so a real bump is still
# a git-visible decision — the override exists for the test harness, not for use.
# Bumped 2026-08-09 (24033 -> 24047, +14) for `project_foundation_redeal_2026_08`,
# the direct sibling of the bump above: same day, same campaign, three more ratified
# verdicts (Готовність keeps 00_03 · prune 00_06 §3 before splitting it · the licensing
# constitution moves 07_03 §3 -> 00_01). It cost 14 B rather than 197 because it took
# NO row of its own — it is hub-inlined under the У-ВЕЙ line it continues, which is the
# cheapest form the policy allows. Funded first: an over-long hook was cut back to its
# trigger and the tool-trial row compressed. ⚠️ The eviction attempted before that was
# WRONG and the gate caught it — dropping the tool-trial row left two `project_*` files
# ORPHAN, because only `log_*` may live on strings alone.
# LOWERED 2026-08-15 (24047 -> 24026, -21) to lock a verified drop, and the
# GROUNDS are written here because the comment at the floor below says exactly
# what nobody checks: a byte drop is a MEASUREMENT, "gain" is a VERDICT. This one
# is the first of the three shapes — prose compressed, nothing displaced, nothing
# deleted. Zero rows removed, zero files removed, zero `[[strings]]` touched; the
# whole 128 B came from (a) six status words duplicating the `✅` glyph they sit
# next to (`SHIPPED` · `RESOLVED` · `DONE` · `COMPLETE` · `ШИПНУТО` · `§🗄️`),
# i.e. one state asserted twice, and (b) ONE volatile count in a hook
# (`(5 осей/4 секції)`), which the index preamble's own write-time rule 3 bans
# outright. ⛔ Nothing was funded by eviction: the only weak candidate is still
# the tool-trial row, and the note above already records why that is refused.
# 2026-08-18: 24026 → 24173 (+147) — one new class-home, `feedback_adversarial_review`,
# and the row was paid HUB-INLINE (a `↳` inside the existing subagent row, not a new
# top-level line), which is why the delta is +147 and not ~300. The class is not a
# guess: §5 was 41% of `feedback_subagent_discipline` and carried FIFTEEN inbound
# `§5` citations, all re-pointed at the new slug in the same pass. Its trigger is the
# one the host file did not serve — "I think I am FINISHED", against that file's
# "I am delegating work".
IDX_BASELINE=${MEMORY_GATE_IDX_BASELINE:-24173}
FILE_CAP=${MEMORY_GATE_FILE_CAP:-40960}          # rule-file ceiling
FILE_WARN=${MEMORY_GATE_FILE_WARN:-36000}        # set just under the known relapse file: it regrew 35->53 kB in 18h
GENRE_MIN=${MEMORY_GATE_GENRE_MIN:-4}            # dated blocks, summed across all three costumes
ONEWAY_MIN=${MEMORY_GATE_ONEWAY_MIN:-2}          # homes citing a source that ignores them, before it is worth a router

# 🔴 RUBY RESOLUTION — because `command -v ruby` answers the wrong question.
#
# Ten of this file's checks are ruby heredocs, and each used to open with
# `command -v ruby || return 0` — a test of PRESENCE, not of FITNESS. Measured
# 2026-08-09, in a live session: the harness PATH led with
# `~/.rvm/gems/ruby-4.0.5@silken_net/bin`, a directory that no longer exists
# (the ruby bump left 3.4.10 and 4.0.6), so `command -v ruby` resolved to
# macOS `/usr/bin/ruby` 2.6.10. Under it one heredoc fails to parse and two
# more die loading `lib/tracker/dashboard.rb`, so NINE of the then-64 selftest
# cases fail — while `--audit` printed `OK` and exited 0. A gate that announces its
# own failure and returns success is the exact shape this repo catalogues.
#
# CI cannot see it: `docs.yml` installs `.ruby-version`, so the battery is
# green there forever. The inversion of "local green ≠ CI" — red precisely
# where the gate actually runs.
#
# Why RESOLVE rather than keep the file 2.6-clean like its neighbour
# `bash_verify_guard.sh`: that pattern works there because its scanner is
# self-contained, whereas `canon_section_check` loads a REPO file. Staying
# 2.6-clean would put a 2.6 ceiling on the tracker parser every gate shares —
# and it would be prose in a comment with nothing enforcing it.
#
# `~/.rvm/rubies/default` is a symlink RVM maintains, so it survives the next
# version bump that broke PATH this time.
resolve_ruby() {
  _c=""
  # An EXPLICIT override is an instruction, not a hint: if the operator named an
  # interpreter and it cannot run the checks, that is an error to report, not a
  # reason to quietly use a different one. This also makes the DARK case
  # testable on any platform — the battery cannot rely on `/usr/bin/ruby` being
  # too old, which is true on macOS and false on a Linux runner (the exact
  # platform split that reddened CI here on 2026-08-09 while local stayed green).
  if [ -n "${MEMORY_GATE_RUBY:-}" ]; then
    [ -x "$MEMORY_GATE_RUBY" ] &&
      "$MEMORY_GATE_RUBY" -e 'exit([].filter_map { |x| x } == [] && eval("def self.__p = 1") ? 0 : 1)' >/dev/null 2>&1 &&
      { printf '%s' "$MEMORY_GATE_RUBY"; return 0; }
    return 1
  fi
  for _c in "$(command -v ruby 2>/dev/null)" \
            "$HOME/.rvm/rubies/default/bin/ruby" /usr/bin/ruby; do
    [ -n "$_c" ] && [ -x "$_c" ] || continue
    # Probe the two features the heredocs actually need — `filter_map` (2.7)
    # and endless method definition (3.0, used by the tracker parser) — rather
    # than a version string, so the check tracks the real dependency.
    "$_c" -e 'exit([].filter_map { |x| x } == [] && eval("def self.__p = 1") ? 0 : 1)' >/dev/null 2>&1 &&
      { printf '%s' "$_c"; return 0; }
  done
  return 1
}
RB=$(resolve_ruby || true)

# 🔴 ONE lantern, every stance [DOC-T.64]. When the probe above fails, every
# ruby-backed check returns 0 WITHOUT RUNNING — an empty finding-set byte-identical
# to "clean". That precondition used to be stated in `--audit` alone: loud in the
# stance you invoke on purpose, silent in the stance that runs on EVERY write. The
# caller passes what did not run (the count differs per stance); the sentence does not.
rb_dark() {
  printf '%s\n%s\n' \
    "DARK  no usable ruby (need filter_map + endless def) — tried \$MEMORY_GATE_RUBY, PATH, ~/.rvm/rubies/default, /usr/bin/ruby" \
    "DARK  ${1:-checks} did not run; this run's silence means nothing until that is fixed (see rvm-heal)"
}

# --- The floor. Every other threshold here is a CEILING, and that asymmetry was
# a hole the whole gate shared: growth was policed from three directions while
# LOSS was not policed at all. Worse than unpoliced — actively rewarded: both
# ratchets below answer a byte drop with "lower the baseline to lock the gain
# in", so a curator who deleted five files got told to cement the deletion, and
# restoring them afterwards would read as the regression.
#
# That is the measurement/verdict substitution in miniature: the byte drop is a
# MEASUREMENT, "gain" is a VERDICT, and nothing checked the grounds. A drop is
# three different events — prose compressed (a real gain), a row displaced into a
# hub (legitimate, iff the strings hold), or a file deleted (amnesia) — and the
# corpus's iron rule is that preservation beats cleanup.
#
# A file count is the one loss signal that needs no stored state: a file vanishes
# only by deletion. The obvious richer detector was BUILT AND REJECTED BY
# MEASUREMENT — "a file with many inbound strings but almost no bytes is a
# gutted home" turns out to describe the corpus's HEALTHIEST genre, the
# skill-pointer stub (`reference_ssot_skill.md` = 1872 B carrying 22 inbound, the
# densest router in the corpus; the smallest file is 945 B and legitimate). Any
# threshold under those numbers is dead, any threshold over them punishes the
# routing layer. Do not rebuild it.
#
# [ceiling] Deletion of a FILE is caught; gutting the CONTENTS of a file that
# stays in place is not — BY THIS PATH. An earlier draft of this comment said
# "and cannot be without storing previous sizes", and that was a claim about a
# MECHANISM made without opening the source: on the Edit path the previous state
# already arrives in the same JSON this gate parses for `file_path`
# (`tool_input.old_string` / `new_string`), so "how many bytes did this edit
# remove" is answerable with no stored state at all — the event carries it.
# Left unbuilt deliberately: a byte-delta threshold needs a DISTRIBUTION of
# legitimate edit sizes before it can have a number, and shipping a guessed floor
# would repeat overlap_check's original sin in a new costume.
#
# MEASURED 2026-08-04 — 1583 unique Edits into this corpus across 223 session
# transcripts, which is the same old_string/new_string pair the hook receives.
# The distribution CLOSES the question rather than supplying the number:
#   * cuts (n=416): median 86 B, p90 612, p95 1034, p99 1789, MAX 3720.
#     A floor must clear 3720 to stay quiet on legitimate work — and gutting is
#     the SAME operation in SMALLER steps, so it never reaches that floor. Dead
#     above, noisy below: no band exists. Exactly overlap_check's pathology, seen
#     from the other side (there the threshold sat over the population maximum;
#     here every threshold must).
#   * the obvious second discriminator also failed: among the 71 deep (>=300 B)
#     body cuts, 66% leave the [[router]] count UNCHANGED, 24% add one, 10% drop
#     one. "A legitimate excision leaves a router behind" is simply not true of
#     the corpus, so router-delta cannot rank the two either. (The 10% that drop
#     a string are already caught — that is UNSTRUNG/DANGLING, not this.)
#   * what the data DOES show is that hollowing arrives as a SERIES, not an
#     event: -20794 B over 37 edits on one file, -29695 B over 176 on the index.
#     No member of such a series is anomalous. Detecting it therefore requires
#     stored state, which this gate does not keep by design — so the ceiling
#     stands, now on measurement instead of assumption.
# Do not rebuild a byte-delta floor. If this is ever reopened, the open question
# is a different one: whether the excised text still exists ANYWHERE in the
# corpus (a shingle lookup of old_string at write time) — and that needs its own
# false-positive measurement first, since any rephrase deletes a unique line.
# (Write is genuinely too late — the file is already replaced — so that half
# would need PreToolUse, a different question.)
# 2026-08-16: 132 → 133 — `log_verify_gate.md`, the journal twin for
# `feedback_verify_gate_exit_code`. Raised so the new home is protected too:
# a floor that lags the corpus stops guarding whatever arrived after it.
# 2026-08-18: 134 → 135 — `log_money_path.md`, same shape: the twin
# `project_money_path_orchestration` had NONE while sitting 306 B from WARN,
# i.e. the file the skill names as "create the twin BEFORE it is needed".
# 2026-08-18: 135 → 136 — `feedback_adversarial_review.md`, split out of
# `feedback_subagent_discipline` (35998 → 21607 B, i.e. 3 B of headroom became 14393).
# 2026-08-18: 136 → 137 — `log_dependabot_sweep.md`, the last home that had no
# journal twin. 34203 → 11626 B, i.e. the whole «Пастки» section (31 bullets)
# moved VERBATIM and the home kept compressed imperatives + routers.
CORPUS_FLOOR=${MEMORY_GATE_CORPUS_FLOOR:-141}

# Index reach — DERIVED, never a constant, and the reason is a correction to an
# earlier draft of this very block. Reach and corpus size count different
# populations (the index deliberately holds no row for a `log_*` — a journal is
# reached by [[string]]), so a reach number compared against the corpus count
# fires on a healthy corpus forever. The first fix was a second constant, and it
# carried two defects an adversarial pass found: (a) no message anywhere invited
# raising it, so every new home widened its blind spot by one — an absolute count
# that silently stops meaning anything, which is the class this file exists for;
# (b) its stated arithmetic was WRONG while its value was right — there are eight
# journals, not nine; the ninth term of the difference is MEMORY.md, which `ls`
# counts and the index never links to itself. A curator "fixing" 114 to 123-8=115
# would have bought a permanent false accusation.
#
# Deriving it removes the constant, the bump ritual and the arithmetic all at
# once: whatever the corpus holds, reach must equal the non-journal files minus
# the index itself.
index_reach_expected() {
  local total logs
  total=$(ls "$MEM_DIR"/*.md 2>/dev/null | wc -l | tr -d ' ')
  logs=$(ls "$MEM_DIR"/log_*.md 2>/dev/null | wc -l | tr -d ' ')
  echo $((total - logs - 1))
}

# The `description:` layer is a THIRD ratchet nobody was watching: it is loaded
# for recall, it is one of the three hand-synced mirrors, and it grew 29 kB ->
# 39.5 kB in two days while both watched surfaces (index, file size) stayed flat.
# A ratchet on the SUM is deliberately chosen over a per-file length rule: the
# rule as written in the index preamble ("no dates/hashes/counts") covers only a
# fifth of the corpus and fires falsely on provenance dates ("ratified 07-26"),
# whereas the sum catches length, state and dates alike with zero classification.
# Bumped 2026-08-01 (39511 -> 41679) for the same three class-homes. Their
# descriptions are dense recall triggers (each names the class, its legs and its
# ⊥ counter-rule), which is exactly what this layer is for; trimming an existing
# recall-rich description to fund them would have traded working recall for a
# number, the manufactured-cleanup this corpus explicitly forbids.
# Bumped 2026-08-03 (41679 -> 41709, +30B) for two new classes earned by TEST.8:
# a 7th substitution layer ("the symptom VARIES with a parameter" — a fact about
# the symptom, not proof the cause depends on it) and a 3rd trigger-leg ("the
# subject itself erases the trigger"). Note what the +30 actually is: the two
# edited descriptions were compressed by ~530B first, so all but the last 30 of
# the 558B added was self-funded — the residue is the new content itself, and
# the alternative was gutting somebody else's trigger to buy back a rounding
# error. Precedent and reasoning identical to the 2026-08-01 bump above.
# Bumped 2026-08-04 (41709 -> 42164, +455) for the same new home. Note what the
# +455 is NOT: the description was written long, measured at +654, and compressed
# by ~200B first — the residue is the new content itself. Trimming somebody else's
# description to buy it back is the manufactured-cleanup this corpus forbids, and
# a DESC bump is structurally unavoidable for ANY new file, so the honest move is
# to record the reason rather than to pretend the layer stayed flat.
# Bumped 2026-08-04 (42164 -> 42686, +522) for the two phase-2 twins
# (log_cross_ref_dig, log_measurement_substitution) that finally gave the two
# saturated rule-homes somewhere to evict into. Their two descriptions weigh
# 582 B, i.e. the layer moved by LESS than the new content — the ratchet had
# 60 B of slack over the actual layer, so this bump also removes that slack.
# Bumped 2026-08-09 (42686 -> 42940, +254) for project_foundation_redeal_2026_08,
# the home of the DOC-T.68/69 Foundation re-deal. Its description was written at
# 579 B and trimmed to 325 B first, so the layer moved by LESS than half the new
# content; the residue is what a new home structurally costs.
# Bumped 2026-08-10 (42940 -> 43088, +148) for log_foundation_redeal — the
# journal-twin of the re-deal home. This is the FIRST bump paid for by a
# receiver rather than by a new claim: the twin took two phase-blocks out of
# a rule-home sitting 278 B under WARN and gave it 4.5 kB of headroom, so the
# description layer grew by one trigger while the corpus got structurally
# healthier. Measured before bumping: the description spread is flat
# (842/793/739/738/714 B at the top), i.e. there was no bloated entry to
# displace — the policy asks for a displacement only when one exists.
#
# 2026-08-16: +86 for `log_verify_gate` — a journal twin created to pull the
# fourth `$?` family's bodies out of a rule-home that had crossed FILE_WARN.
# Same shape as above: the new trigger was already written at ~160 chars,
# half the corpus median (321), so trimming it further would be manicure, and
# nothing else was bloated enough to displace. The eviction it enabled took
# its home 36876 → 35332 B, i.e. the layer grew by one line and a WARN closed.
# 2026-08-18: 43174 → 43268 (+94), and the shape repeats the entry above almost
# exactly. `log_money_path.md` is a new journal twin; its trigger was drafted at
# 274 B, trimmed to 131 B to match its sibling `log_local_verify`, and further
# trimming would be manicure — 131 B is well under the corpus median. Nothing
# else was bloated enough to displace, and cutting another file's recall trigger
# to fund a new home is the manufactured-cleanup this practice forbids. What the
# eviction bought: its home went 35694 → 32408 B, i.e. 306 B of headroom became
# 3592 and a file the skill had flagged as twinless stopped being one.
# 2026-08-18: 43268 → 43583 (+315) — the new home's own trigger. Same shape as the
# entry above it: a description is what a class costs to be FINDABLE, and this class
# was already being cited fifteen times without one.
# 2026-08-18: 43583 → 43755 (+172) — the last journal twin's own trigger, same
# shape as the two entries above. With it the twinless set is EMPTY, so this
# particular reason for a bump cannot recur.
DESC_BASELINE=${MEMORY_GATE_DESC_BASELINE:-43755}

# Content-overlap between two files. The corpus has ONE structural failure mode
# no other check can see: a class written into two homes, where every link
# resolves and only the prose contradicts (proven live — one commit was called
# "the single living record" by two files at once).
#
# REBUILT 2026-08-04 (DOC-T.59). The previous shape — shingles over the WHOLE
# file, absolute floor 120 — was not merely blunt, it was DEAD: measured across
# all 6441 pairs of the live corpus the maximum overlap is 72, so the floor sat
# at 167% of the physical maximum and could never fire, on any corpus state. It
# is the "a gate over an empty set is green forever" class, living inside the
# gate meant to catch duplication. Two known duplicates measured 63 and 20 —
# both inside the "a home cites its source" band the floor was calibrated to
# ignore. The cause is dimensional: an absolute floor over a whole-FILE shingle
# set asks "do these files share 120 six-grams", while a duplicated RULE is one
# paragraph — 60 words can never reach 120 no matter how many times it is copied.
#
# The unit is now the BLOCK (bullet or paragraph) and the measure is the overlap
# COEFFICIENT — |A∩B| / min(|A|,|B|) — which is scale-free, so a fully duplicated
# 60-word rule scores ~1.0 exactly like a duplicated 600-word one.
#
# Two filters, both measured rather than guessed. (1) The frontmatter: description
# fields are structurally alike across the corpus. (2) Our OWN router idiom
# ("**Клас цієї відмови має дім:** [[x]] — …", 4 forms, 22 instances) is a
# DELIBERATE mirror standing verbatim in N files; unfiltered it produced every
# single top hit at coefficient 1.00. Restricted to SHORT blocks so a substantive
# paragraph that merely mentions the idiom is not swallowed.
#
# Journals are NO LONGER exempt, and that exemption was hiding all of the measured
# debt: every one of the seven live hits lives in a log_*. The old rationale
# ("holding the chronicle verbatim is their job") is true of INSTANCES — dates,
# numbers, what happened — but a journal restating a home's MAXIM word-for-word
# is not chronicle, it is the phase-2 debt the consolidation recipe exists to
# prevent. The router test below separates the two without needing the exemption.
#
# The router test is what makes this a debt detector rather than a similarity
# meter: a source that carries [[home]] INSIDE the overlapping block is the
# recipe's prescribed shape ("instance + router") and stays silent; a block that
# restates the rule with no pointer is the case where the two copies will drift
# and only one will be updated. A file-level link elsewhere does NOT count — the
# reader of THIS block never sees it.
#
# Mutation-verified on a corpus clone, all three arms: a verbatim rule copied into
# a foreign file WITHOUT a router fires (7 -> 8); the same copy WITH a router in
# the block goes silent (back to 7, so the router test carries weight rather than
# decorating); the same class REPHRASED stays silent.
#
# [ceiling] That third arm is the honest limit: shingles see verbatim copies only,
# so a rule restated in different words is invisible here BY CONSTRUCTION. This
# gate is therefore necessary but not sufficient — the paraphrased half is found
# by READ-based inventory (the consolidation recipe's step 3), never by this
# number. Do not read a green overlap_check as "no duplicate homes"; read it as
# "no VERBATIM duplicate homes". Upgrade path, if the paraphrased half ever needs
# machine coverage: embeddings, which this corpus deliberately does not have — the
# working substitute is the topology of [[strings]].
OVERLAP_COEF=0.45       # share of the smaller block; 0.45 caught both known duplicates
OVERLAP_MIN_SHINGLES=15 # ~20 words: below this, headers and router lines dominate

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
    # Say that this line IS the red, not that headroom remains. The old wording
    # printed only the CAP, so a reader at 36 kB read "5 kB to go" while the
    # battery had already gone EXIT 1 on this very line — the gate describing
    # one quantity while measuring another. Both numbers, and which one bites.
    echo "WARN  $f = ${sz}B — over the working ${FILE_WARN}, so this line alone makes --audit EXIT 1 (hard ceiling ${FILE_CAP}); evict instances to its log_* twin"
  fi
  # The verdict wording was the defect. "Chronicle inside a rule file" reads as a
  # sentence, and the triage that makes it safe — keep a block that carries a
  # CLASS plus a reflex, evict one that REPORTS a run — lived only in the
  # housekeeping prompt, which nothing loads automatically. So the one line that
  # actually reaches the person about to cut said the opposite of the rule.
  #
  # The router false positive is measured, not hypothetical: on the worst file 3
  # of 4 hits were migration routers ("N rules moved to <home> (date)"), i.e. the
  # detector cried chronicle at a file that had just SHED its chronicle. Widening
  # or narrowing the regex cannot separate them — a router is a dated bold span
  # exactly like a report — so the cure is on the WRITING side, and it belongs in
  # this message because that is where the router's author is standing.
  if [ "$sum" -ge "$GENRE_MIN" ]; then
    echo "GENRE $f carries $sum dated blocks (h/l/b = $shape) — a TRIGGER to read them, not a verdict:"
    echo "      keep a block carrying CLASS + reflex (strip its date wrapper only), evict one that REPORTS a run;"
    echo "      a migration-router line (\"N rules moved to <home> (date)\") matches here and is a FALSE positive — drop its non-load-bearing date instead"
  fi
  return 0
}

# A backticked path that CLAIMS our tree (starts with a real repo root) is a
# checkable assertion; anything else — gem internals (`aasm/base.rb`), a bare
# `queen/main.c` shorthand — is not, and checking those only yields noise the
# gate gets muted for.
#
# A dead path is one of THREE things, and the third is not a defect at all:
# it MOVED (a stale mirror — cheap), it was RETRACTED (the repo deleted the claim
# as untrue and memory is now the last living copy of a deleted untruth), or
# memory DELIBERATELY records a removed file as part of a decision and says so
# outright («носія в дереві нема»). The first two are separated only by the commit
# body, so the message says so; the third cannot be inferred at all and is
# therefore DECLARED here — a `†` tombstone glued to the closing backtick of the
# citation. The backtick itself stays: it names a tool that existed, and dropping
# it would make the historical record less true. (No example path is spelled out
# in this comment on purpose — an illustrative path is byte-identical to a live
# claim, and three separate gates in this repo resolve such paths against disk.)
#
# Why a marker and not the prose it sits in: measured on the live corpus, honest
# retirement notes stand 71..354 chars from their citation (one bullet carries
# five of them under a single «Що знято» frame), so any window wide enough to
# bless them is the whole bullet — while 17 LIVE path citations already share a
# line with retirement wording about something else. Lexical inference would mute
# more future deaths than it excuses present notes. The glyph is not invented for
# this: the corpus already spells a person's death `†2024`.
#
# The marker is per-CITATION, not per-line and not per-file: a path cited once
# bare and once entombed still reds on the bare one, because a claim is blessed
# only where it is annotated. The fourth quadrant is its own check — a tombstone
# over a file that EXISTS is the same lie pointing the other way (the file came
# back, or never left), so TOMBLIVE fires. Forgetting the † is loud, never silent.
PATH_ROOTS='app|lib|scripts|docs|firmware|contracts|config|db|spec|tools|bin|deploy|terraform|subgraph|\.claude|\.github'

path_check() {
  local f=$1 e p
  # `(†)?` is grouped deliberately. A bare `†?` binds the quantifier to the last
  # BYTE of the 3-byte glyph under a C locale, which would make the marker
  # MANDATORY and silence every un-annotated claim — the gate would go quiet in
  # exactly the direction it exists to prevent. Grouping is byte-safe in both
  # BSD and GNU grep, so the check cannot behave differently here and on a runner.
  for e in $(grep -ohE '`('"$PATH_ROOTS"')/[a-zA-Z0-9_./-]+\.[a-z]{1,4}`(†)?' "$f" 2>/dev/null |
               sed 's/`†$/`:TOMB/' | sort -u); do
    case $e in
      *:TOMB)
        p=$(printf '%s' "${e%:TOMB}" | tr -d '`')
        [ -e "$REPO/$p" ] &&
          echo "TOMBLIVE $(basename "$f") marks \`$p\`† as removed — the file EXISTS; drop the † or fix the claim around it" ;;
      *)
        p=$(printf '%s' "$e" | tr -d '`')
        [ -e "$REPO/$p" ] ||
          echo "DEADPATH $(basename "$f") cites \`$p\` — gone from the repo; \`git log --diff-filter=D -- $p\` says whether it MOVED or was RETRACTED, and \`$p\`† declares a deliberate tombstone" ;;
    esac
  done
  return 0
}

# Every other check iterates "$MEM_DIR"/*.md, so a file WITHOUT that extension
# receives nothing: no format check, no cap, no reachability — and a backticked
# mention of it from the md side resolves against nothing either. At least one
# such resident is deliberate (a toolchain-repair copy kept here precisely
# because transcripts get purged), which is exactly why a housekeeping sweep
# must not quietly take it along with the .bak files. Both directions, because
# the expensive failure is the silent one: the asset disappearing unnoticed.
# Measured on the live corpus: 0 firings in either direction.
asset_check() {
  local f bn
  for f in "$MEM_DIR"/*; do
    bn=$(basename "$f")
    case $bn in *.md|.*) continue ;; esac
    grep -qF "$bn" "$MEM_DIR"/*.md 2>/dev/null ||
      echo "RESIDENT $bn — a non-.md file no memory mentions: leftover, or an asset a sweep is about to take"
  done
  for bn in $(grep -ohE 'memory-dir[^`]*`[A-Za-z0-9._-]+\.[a-z]{2,7}`' "$MEM_DIR"/*.md 2>/dev/null |
                grep -oE '`[A-Za-z0-9._-]+\.[a-z]{2,7}`$' | tr -d '`' | sort -u); do
    [ -f "$MEM_DIR/$bn" ] ||
      echo "GONE    $bn — memory says this asset lives in the corpus; it does not"
  done
  return 0
}

# Two files hold the founder's personal circumstances (medical, psychological,
# precise location). This gate CANNOT enforce read access — it sees writes, not
# reads, and a subagent spawned for any memory task reads the whole corpus by
# default. What it can do is notice the marker DISAPPEARING, which is the
# realistic failure: a rewrite drops frontmatter silently, and the next curator
# has nothing telling them this file must not travel into an agent brief.
# Curated list, deliberately short — a long one would be a classification
# scheme nobody maintains.
PRIVATE_FILES='user_life_context.md user_location_cherkasy.md'

privacy_check() {
  local f
  for f in $PRIVATE_FILES; do
    [ -f "$MEM_DIR/$f" ] || continue
    grep -q '^[[:space:]]*sensitivity: private' "$MEM_DIR/$f" ||
      echo "PRIVACY $f lost its \`sensitivity: private\` marker — restore it; this file must stay out of subagent briefs"
  done
  return 0
}

# Sum of every `description:` field, in bytes. Cheap enough for the write path.
desc_check() {
  # [ceiling, measured 2026-08-04 — do NOT rebuild] This ratchet is SUM-only, and a
  # per-file "fat description" threshold was designed and REJECTED by measurement.
  # Distribution over all 122 files: median 321 · p75 467 · p90 632 · p95 684 · max 952.
  # The tail is not the disease — it is `mechanism_vs_its_trigger` (952), the
  # `measurement_substitution`/`irreversibility_proof_bar` pair (827/826), `silent_default`
  # (777) and `founder_push_signals` (723), i.e. the error-axis homes, whose recall trigger
  # legitimately carries several layers. Any threshold under those numbers punishes the
  # richest homes in the corpus; any threshold above them is dead. Same shape as the
  # rejected "many strings, few bytes = gutted home" detector, which described skill-pointer
  # stubs — the healthiest genre. The sum ratchet is the right form precisely because it
  # lets ONE home be fat while the rest stay tight. What a per-file rule cannot see, and
  # no counter can, is whether the description DUPLICATES the body or is its only home —
  # that verdict needs a READ (verify-before-delete), not a number.
  local tot
  # Counted in ruby, not awk, and that is a finding rather than a preference:
  # the identical logic in BSD awk under-reported this layer by ~7% across the
  # multi-file run while agreeing to the byte on any single file — so the number
  # was wrong in exactly the way that never looks wrong. Whatever counts this
  # must agree with `bytesize`; verify a new implementation against one file AND
  # the whole corpus before trusting it.
  [ -n "$RB" ] || return 0
  tot=$("$RB" - "$MEM_DIR" <<'RUBY'
dir = ARGV[0]
total = 0
Dir.chdir(dir) { Dir["*.md"] }.each do |f|
  next if f == "MEMORY.md"
  fm = File.read(File.join(dir, f))[/\A---\n(.*?)\n---\n/m, 1] || ""
  total += fm[/^description:\s*(.*(?:\n\s+.*)*)/, 1].to_s.strip.bytesize
end
puts total
RUBY
)
  [ "$tot" -gt "$DESC_BASELINE" ] &&
    echo "DESC  description layer = ${tot}B, past its ${DESC_BASELINE}B ratchet (+$((tot - DESC_BASELINE))) — a description is a recall TRIGGER, not a log; trim one before adding one"
  # Same discrimination as the index ratchet: this layer shrinks when descriptions
  # are compressed (a gain) and equally when files are deleted (a loss), and the
  # sum cannot tell them apart. So the invitation to cement is withheld while the
  # corpus is short a file — otherwise the gate cements the amnesia.
  if [ "$tot" -lt $((DESC_BASELINE - 800)) ]; then
    if [ "$(ls "$MEM_DIR"/*.md 2>/dev/null | wc -l | tr -d ' ')" -lt "$CORPUS_FLOOR" ]; then
      echo "DESC  description layer = ${tot}B, well below its ${DESC_BASELINE}B ratchet — but the corpus is short a file"
      echo "      the drop is missing descriptions, not tighter ones: settle FLOOR first"
    else
      echo "DESC  description layer = ${tot}B, well below the ${DESC_BASELINE}B ratchet — lower DESC_BASELINE here to lock the gain in"
    fi
  fi
  return 0
}

# One class living in two homes. --audit only: O(n^2) over shingle sets is too
# slow for a PostToolUse hook, and this failure mode is not introduced by a
# single write anyway — it accumulates. Measured cost at the current corpus:
# 1.4M block pairs in ~1.3s.
overlap_check() {
  [ -n "$RB" ] || return 0
  "$RB" - "$MEM_DIR" "$OVERLAP_COEF" "$OVERLAP_MIN_SHINGLES" <<'RUBY'
require "set"
dir, coef_floor, min_sh = ARGV[0], ARGV[1].to_f, ARGV[2].to_i
files = Dir.chdir(dir) { Dir["*.md"] }.reject { |f| f == "MEMORY.md" }

words = ->(t) { t.downcase.gsub(/[^\p{L}\p{N}\s]/, " ").split }
shingles = ->(t) { words.(t).each_cons(6).map { |c| c.join(" ").hash }.to_set }

# A block is a bullet (with its continuation lines) or a paragraph.
split_blocks = lambda do |text|
  out, cur = [], []
  text.each_line do |line|
    if line.strip.empty?
      out << cur.join(" ") unless cur.empty?
      cur = []
    elsif line =~ /^\s*[-*]\s/ || line =~ /^\#{1,6}\s/
      out << cur.join(" ") unless cur.empty?
      cur = [line]
    else
      cur << line
    end
  end
  out << cur.join(" ") unless cur.empty?
  out
end

# Deliberate mirrors, not duplication: a list of [[strings]], a Related line, and
# our own "клас X має дім" router sentence — the last one produced EVERY top hit
# before it was filtered.
boilerplate = lambda do |t|
  w = words.(t).size
  next true if w.zero?
  links = t.scan(/\[\[[^\]]+\]\]/).size
  next true if links >= 3 && links * 4.0 / w > 0.25
  next true if w < 50 && links >= 1 && t =~ /має\s+(власний\s+)?дім\s*[:»]/i
  next true if w < 60 && t.strip.start_with?("**Related", "Related")
  false
end

blk = {}
files.each do |f|
  body = File.read(File.join(dir, f)).sub(/\A---\n.*?\n---\n/m, "")
  split_blocks.(body).each_with_index do |b, i|
    next if boilerplate.(b)
    s = shingles.(b)
    next if s.size < min_sh
    blk[[f, i]] = [s, b.scan(/\[\[([a-zA-Z0-9_-]+)\]\]/).flatten.to_set]
  end
end

blk.keys.combination(2) do |ka, kb|
  next if ka[0] == kb[0]
  inter = (blk[ka][0] & blk[kb][0]).size
  next if inter < 8
  coef = inter.to_f / [blk[ka][0].size, blk[kb][0].size].min
  next if coef < coef_floor
  # The prescribed shape is "instance + router". A pointer INSIDE the overlapping
  # block means the copy knows where its rule lives; anything else drifts silently.
  next if blk[ka][1].include?(kb[0].sub(/\.md\z/, "")) ||
          blk[kb][1].include?(ka[0].sub(/\.md\z/, ""))
  puts format("OVERLAP %s#%d and %s#%d share %d%% of the smaller block (%d 6-grams) " \
              "with no [[router]] between them — one rule, two homes: keep the rule in ONE " \
              "and leave \"instance + router\" in the other",
              ka[0], ka[1], kb[0], kb[1], (coef * 100).round, inter)
end
RUBY
  return 0
}

# The corpus-size pin: fires BOTH ways (under = loss, over = a new home that has
# not been protected yet). Deliberately counts files rather than bytes: bytes fall
# for three different reasons and only one of them is a loss, while a .md
# disappearing is unambiguous.
#
# [ceiling] It is a NET count, and that blindness is structural: a deletion inside
# a session that also adds a file is invisible, and the over-branch will even
# invite raising the floor — cementing the loss it was built to catch. Nothing
# stateless fixes this; what does is procedure, so the housekeeping recipe ends
# with a final `--audit` rather than opening with one. Note also that the loss
# EVENT is unobservable here in the common case: files are removed with `rm`,
# and the hook matcher is Edit|Write, so the floor speaks at the next write.
corpus_floor_check() {
  local n
  n=$(ls "$MEM_DIR"/*.md 2>/dev/null | wc -l | tr -d ' ')
  if [ "$n" -lt "$CORPUS_FLOOR" ]; then
    echo "FLOOR corpus holds ${n} .md files, below its ${CORPUS_FLOOR} floor ($((CORPUS_FLOOR - n)) gone)"
    echo "      preservation beats cleanup: restore them, or — if a merge genuinely"
    echo "      absorbed them — lower CORPUS_FLOOR here, which makes the loss git-visible"
  elif [ "$n" -gt "$CORPUS_FLOOR" ]; then
    echo "FLOOR corpus grew to ${n} .md files (floor ${CORPUS_FLOOR}) — raise CORPUS_FLOOR here so the new homes are protected too"
  fi
  return 0
}

# Index links, counted as UNIQUE targets rather than rows: hub-inlining collapses
# thirteen rows into two without dropping a single pointer, so rows measure layout
# and links measure reach. The routing layer is what a byte drop can quietly cost.
# ONE definition of "an index row's markdown link to a corpus file". It had three
# copies, and widening one of them alone is worse than widening none: a dash- or
# capital-bearing name then reads as a LIVE link to integrity_check while the two
# reach counters still miss it, so a healthy corpus gets accused of eviction —
# the ratchet's own worst failure mode, advice on a false basis.
IDX_LINK_RE='\]\([a-zA-Z0-9_-]+\.md\)'
index_links() { grep -oE "$IDX_LINK_RE" "$IDX" | sort -u | wc -l | tr -d ' '; }

# Every threshold is env-overridable so --selftest can build a fixture, and that
# convenience quietly made the verdict unfalsifiable: an exported
# MEMORY_GATE_CORPUS_FLOOR=1 disarms the floor forever with no indication, and
# "OK" would still print. A green verdict computed against somebody else's
# thresholds is exactly the self-attestation this file polices, so it is reported
# — and it is reported as a FINDING (non-zero exit), because a run whose numbers
# did not come from the file cannot be read as the file's verdict. The self-test
# announces itself and is exempt; nothing else is.
override_check() {
  [ "${MEMORY_GATE_SELFTEST:-0}" = "1" ] && return 0
  local v
  v=$(env | grep '^MEMORY_GATE_' | grep -v '^MEMORY_GATE_SELFTEST=' | cut -d= -f1 | tr '\n' ' ')
  [ -n "$v" ] &&
    echo "OVERRIDE thresholds came from the environment, not this file: ${v}— the verdict below is not the corpus's, unset them and re-run"
  return 0
}

index_check() {
  local sz n links
  sz=$(wc -c <"$IDX" | tr -d ' ')
  n=$(grep -cE "^[[:space:]]*- .*$IDX_LINK_RE" "$IDX")
  links=$(index_links)
  if [ "$sz" -gt "$IDX_BASELINE" ]; then
    echo "INDEX MEMORY.md = ${sz}B, past its ${IDX_BASELINE}B ratchet (+$((sz - IDX_BASELINE)), ${n} entries)"
    echo "      a new entry earns its line only by displacing one; detail belongs in the file"
  elif [ "$sz" -lt $((IDX_BASELINE - 400)) ]; then
    # "Smaller" is not "better" until you know WHICH of the three events it was.
    # Reach is the discriminator the old wording never asked for: compression and
    # hub-inlining both hold the link count, only eviction drops it.
    if [ "$links" -lt "$(index_reach_expected)" ]; then
      echo "INDEX MEMORY.md = ${sz}B, below the ${IDX_BASELINE}B ratchet — but it routes to only ${links} files"
      echo "      that is eviction, not compression: do NOT lower the ratchet until every"
      echo "      dropped file is reachable again (a hub row, or an inbound [[string]])"
    else
      echo "INDEX MEMORY.md = ${sz}B, below the ${IDX_BASELINE}B ratchet, reach intact (${links} files) — lower IDX_BASELINE here to lock the gain in"
    fi
  fi
  return 0
}

# Reachability of every journal, extracted so BOTH stances can run it. Living
# only in --audit was a real hole, proven by probe: an Edit that severs a
# journal's last string is SILENT at the moment of action — and rewriting a rule
# file is exactly when that happens, which is the operation this gate exists for.
# --- One-way provenance. A rule-home cites a journal or a project file as the
# instance that produced it, and the source carries nothing back. The reader of
# the SOURCE therefore never learns the rule already has an address, so the next
# consolidation pass re-derives the whole class from zero — which is exactly how
# two consecutive waves each rediscovered the same classes, and why phase-2
# numbers kept rising instead of converging.
#
# Deliberately OUTSIDE --audit: the live count runs to dozens, so folding it into
# the battery would make EXIT 1 permanent and train the reader to skim the one
# stance that must stay loud. This is a WORKLIST, not a verdict.
#
# 🔴 The old wording here said "same stance as GENRE", and that was FALSE in the
# way this file is meant to police: `--genre` is a corpus-wide LENS, but the GENRE
# FINDING rides check_file and therefore sits INSIDE --audit and gates. The two are
# separated by YIELD, not by subject — GENRE's live yield is zero, so it belongs in
# the battery; this one's is dozens, so it cannot. Both are triggers to go read a
# file; only one of them can afford to be loud. (There is no mechanical form for
# this class of lie: the claim is an analogy between a mode and a finding, and no
# function name appears in it — so it is prose, and it is corrected as prose.)
#
# Grouped by TARGET rather than by source, because the router is written into
# the target: one edit there can answer several homes at once. And the unit is
# COVERAGE (how many homes cite a file that ignores them), never bytes — adding
# a router to a project_* source GROWS it, so a byte metric would score the
# correct fix as a regression. That inversion is the whole reason this axis went
# unmeasured: every other threshold in this file is a size.
oneway_check() {
  [ -n "$RB" ] || return 0
  "$RB" - "$MEM_DIR" "$ONEWAY_MIN" <<'RUBY'
dir, min = ARGV[0], ARGV[1].to_i
files = Dir["#{dir}/*.md"].map { |p| File.basename(p, ".md") } - ["MEMORY"]
present = files.each_with_object({}) { |f, h| h[f] = true }
links = files.each_with_object({}) do |f, h|
  h[f] = File.read(File.join(dir, "#{f}.md"))
          .scan(/\[\[([^\]\n]+)\]\]/).flatten.map(&:strip)
          .select { |t| present[t] }.uniq
end
# A home's PROVENANCE strings only. A `Related:` / `See [[…]]` line is a PEER
# cross-reference — one-way BY DESIGN, and the memory-maintenance skill already
# declares it so. Counting those as provenance made this detector systematically
# overstate: of the four pairs it reported on 2026-08-05, three sat on peer lines
# and only one was a real rule-with-`→`-router. Measured over the whole corpus:
# 25 of 316 home→source strings live on such lines, and a read of all 25 found
# zero provenance among them, so the exclusion cannot hide a real pair.
peer = /\A\s*(\*\*)?Related\b/i
prov = files.each_with_object({}) do |f, h|
  h[f] = File.readlines(File.join(dir, "#{f}.md"))
          .reject { |l| l =~ peer || l.include?("See [[") }
          .join.scan(/\[\[([^\]\n]+)\]\]/).flatten.map(&:strip)
          .select { |t| present[t] }.uniq
end
by_target = Hash.new { |h, k| h[k] = [] }
files.each do |home|
  next unless home.start_with?("feedback_", "reference_")
  prov[home].each do |src|
    next unless src.start_with?("log_", "project_")
    next if links[src].include?(home)   # reciprocated — not this class
    by_target[src] << home
  end
end
by_target.sort_by { |t, homes| [-homes.size, t] }.each do |t, homes|
  next if homes.size < min
  puts format("ONEWAY %-40s cited as provenance by %d home(s) it never points back at: %s",
              t, homes.size, homes.join(", "))
end
RUBY
  return 0
}

# Every file needs an inbound string, not only a journal. The journal-only form
# was the same half-fix UNSTRUNG itself once was: the EVENT is an edit that severs
# the last string, and that edit is no likelier to land on a journal than on a
# rule file. A non-journal keeps its index row and quietly stops resonating — and
# the row is the weaker of the two carriers, since the reconstruction of first-read
# addresses put strings ahead of it and found NO systemic reminder behind either.
#
# Measured on the live corpus the day this widened: 125 files, ZERO with in=0. So
# it pins an invariant the corpus already holds rather than opening a worklist —
# that yield test is what decides battery-vs-worklist one level up.
#
# Self-citation does NOT count, and that hole was in the journal-only version:
# `grep -r` over the whole dir matches the file itself, so a file naming its own
# slug certified its own reachability. Reachability is a claim about the REST of
# the corpus by definition.
#
# Named `*_check` deliberately: the parity detector scans for that suffix, so the
# old name kept a stance-running check outside its reach.
unstrung_check() {
  [ -n "$RB" ] || return 0
  "$RB" - "$MEM_DIR" <<'RUBY'
dir   = ARGV[0]
files = Dir[File.join(dir, "*.md")].map { |p| File.basename(p, ".md") } - ["MEMORY"]
inbound = Hash.new(0)
(files + ["MEMORY"]).each do |src|
  path = File.join(dir, "#{src}.md")
  next unless File.exist?(path)
  File.read(path).scan(/\[\[([^\]\n]+)\]\]/).flatten.map(&:strip).uniq.each do |t|
    inbound[t] += 1 unless t == src
  end
end
files.sort.each do |f|
  next unless inbound[f].zero?
  puts(f.start_with?("log_") ?
    "UNSTRUNG #{f}.md is a journal nothing links to — it has no index row either, so it is unreachable" :
    "UNSTRUNG #{f}.md has an index row but nothing links to it — a row orients on the first read, the string is what carries recall afterwards")
end
RUBY
  return 0
}

# A string that resolves to a live file but promises a SECTION that is not there.
# The link is intact, the file exists, integrity_check is green — and the reader
# lands in nothing. This is the corpus's most densely documented illness (a class
# was re-pointed at §F4 after it had moved out of F4; a split left an index row
# quoting two clauses no longer in the file) and it had no gate at all.
#
# Scope is deliberately the NARROWEST form that carries proof, and the two wider
# designs were BUILT AND REJECTED BY MEASUREMENT, so do not rebuild them:
#   - "quoted claim anywhere on the line" -> 382 candidates, i.e. noise. A quote
#     sitting near a string is not a claim ABOUT its target, and the corpus is
#     bilingual, so quote-matching is a false-negative machine by construction
#     (a hook citing «чи цій skill-gotcha треба ще одна гілка?» is honest — the
#     target states it in English).
#   - "any §-address on the line" -> 29 hits, nearly all false: F1-F7 are the
#     SOURCE's own sections, Guard-craft lives in a skill, not in the corpus.
# Adjacency is what makes the reference unambiguous: `[[file]] §Name` names a
# section OF that file and nothing else.
#
# [ceiling] Covers explicit §-addresses adjacent to a string — 43 claims on the
# live corpus. A promise made in PROSE ("the recipe lives there") is out of reach
# here and is caught only by reading. Measured 2 dead of 43, both true defects
# and of DIFFERENT shapes: an address written in the other language, and the
# source's own section offered as the target's.
section_ref_check() {
  [ -n "$RB" ] || return 0
  "$RB" - "$MEM_DIR" <<'RUBY'
dir = ARGV[0]
files = Dir.chdir(dir) { Dir["*.md"] }
body = files.to_h { |f| [f, File.read(File.join(dir, f))] }

pats = [
  [/\[\[([a-zA-Z0-9_-]+)\]\][\s,—-]{0,3}(?:§\s?)([A-Za-zА-Яа-яЇїІіЄєҐґ][\w\-]{2,24})/, :fwd],
  [/\[\[([a-zA-Z0-9_-]+)\]\][\s,—-]{0,3}\b(F[1-9])\b/,                                  :fwd],
  [/(?:§\s?)([A-Za-zА-Яа-яЇїІіЄєҐґ][\w\-]{2,24})\s+\[\[([a-zA-Z0-9_-]+)\]\]/,           :rev],
]

files.each do |f|
  body[f].each_line.with_index do |line, ln|
    pats.each do |re, dir_kind|
      line.scan(re) do |a, b|
        tgt, addr = dir_kind == :rev ? [b, a] : [a, b]
        tf = "#{tgt}.md"
        next unless body.key?(tf)
        t = body[tf]
        next if t.include?("§#{addr}")
        next if t.match?(/(^|[\s*`(])#{Regexp.escape(addr)}([\s*`).,:]|$)/)
        next if t.each_line.select { |l| l =~ /^#+\s/ }
                 .any? { |h| h.downcase.include?(addr.downcase) }
        puts "SECREF  #{File.basename(f)}:#{ln + 1} sends the reader to #{tf} §#{addr} — " \
             "that section is not there: fix the address or the target"
      end
    end
  end
end
RUBY
  return 0
}

# ── canon `NN_NN §X` refs inside memory — the corpus nobody scanned ─────────
# Memory cites canon sections exactly like code and skills do, and until
# 2026-08-04 NO gate looked at them [DOC-T.60]: `code_doc_section_refs.rb`
# walks app/spec/lib + .claude, and this corpus lives OUTSIDE the repo, so CI
# cannot reach it by construction. That is precisely the surface an agent
# quoted a dead `04_06 §A.10а` back from as canonical. So the check's home is
# HERE rather than that script's TREES: this gate already knows $REPO, already
# runs on both stances, and a wrong address is born at the moment of writing.
# The resolver is REUSED, never reimplemented — a second §-resolver would drift
# from the four gates sharing the first one, which is the whole failure mode
# this family exists to prevent.
canon_section_check() {
  [ -n "$RB" ] || return 0
  [ -f "$REPO/lib/tracker/dashboard.rb" ] || return 0
  "$RB" - "$MEM_DIR" "$REPO" <<'RUBY'
dir, repo = ARGV
begin
  require File.join(repo, "lib", "tracker", "dashboard")
rescue Exception => e
  # 🔴 This used to be a bare `exit 0` with the comment "silent, never a false
  # alarm" — and that comment was the defect, not the code. Two states are
  # indistinguishable to a caller reading silence: "the repo is not here, so
  # there is nothing to check" (legitimate) and "the resolver would not load,
  # so CANONREF and CANONREF-EXEMPT-DEAD did not run at all" (a hole). Under
  # macOS ruby 2.6 the second one was live and mute. A gate may decline to
  # check; it may not decline QUIETLY, because its silence is read as a
  # verdict. Missing repo stays silent; anything else says so and reds.
  if File.directory?(File.join(repo, "lib"))
    # stdout, not stderr: `--audit` captures stdout into `out` and decides the
    # exit code by `[ -z "$out" ]`, so a warning on stderr would print beside a
    # green verdict — loud and ignored, which is the disease, not the cure.
    puts "DARK  canon_section_check did not run — #{e.class}: #{e.message.lines.first.to_s.strip[0, 120]}"
    puts "DARK  its silence means nothing; CANONREF + CANONREF-EXEMPT-DEAD are unguarded this run"
    exit 3
  end
  exit 0
end
# Curated exemptions, same posture as the SPDX gate's DENY list: a DECIDED case
# is recorded with its reason so the gate never sits permanently red on it, and
# the detector stays live for every new ref. Keyed per file, so an exemption
# never blinds a whole file the way a path-level EXEMPT would.
# ── Dissolved-module citations [DOC-T.68 фаза 0, 2026-08-10] ──────────────────
# Ten refs to Module 08 and to 00_04 surfaced the day the §-resolver went
# fail-CLOSED. They had been invisible, not absent. Each was read in context and
# the test was «is the SUBJECT of this sentence the ADDRESS or the FACT», which
# came back unanimous: every one records a past ACTION — "that section was
# rewritten", "the dead path CODEOWNERS carried was this one", "BIZ.20 moved
# FROM here", "the fix landed there" — plus one deliberate teaching citation
# (range prose quoted as the specimen of a semantic tail after a mass delete).
# So the address is part of the fact, not navigation to content: re-pointing
# would make the sentence FALSE, and deleting the address would destroy the
# record. History does not move when the docs do.
# ⚠️ This is the widest exemption block in the gate, so note what still holds:
# it is per-FILE and per-REF, `CANONREF-EXEMPT-DEAD` reds if any of these stops
# being a dangling ref (the entry then guards nothing), and every NEW citation
# of a dissolved doc is still caught — the detector stays live.
exempt = {
  # The renumber-drift teaching case: `§749` is a LINE number written as a
  # section — citing it IS the lesson. `code_doc_section_refs.rb` exempts the
  # ssot-maintenance skill for this same ref, for this same reason.
  "project_ssot_campaign_history.md" => ["05_03 §749", "08_03 §11", "08_01 §2"],
  "log_portfolio_surgery.md" => ["08_03 §9", "08_03 §15"],
  "project_ip_posture_defensive_publication.md" => ["08_01 §2"],
  "project_uwei_process_layer_cut.md" => ["00_04 §2"],
  "project_vilize_07_08.md" => ["08_01 §0.1", "08_02 §2", "08_03 §2", "08_02 §5"]
}
# Test seam, same shape as the MEMORY_GATE_* overrides elsewhere: the curated
# table names a real corpus file, which no fixture repo has, so the self-test
# could not reach the staleness check without one. Format `file.md|ref`.
if (extra = ENV["MEMORY_GATE_CANONREF_EXEMPT_EXTRA"])
  f, r = extra.split("|", 2)
  (exempt[f] ||= []) << r if f && r
end
# Resolve against the docs of the repo we were POINTED AT, never the one the
# resolver happens to sit in — otherwise the fixture would silently answer with
# the live tree, which is exactly the non-hermetic shape DEADPATH just outgrew.
docs = File.join(repo, "docs")
exit 0 unless Dir.exist?(docs)
used = Hash.new { |h, k| h[k] = [] }
scanned = Dir.chdir(dir) { Dir["*.md"] }.sort
scanned.each do |f|
  Tracker::Dashboard.file_section_dangling_refs(File.read(File.join(dir, f)), docs).each do |h|
    ref = h.to_s.delete("`")
    if (hit = exempt.fetch(f, []).find { |e| ref.include?(e) })
      used[f] << hit
      next
    end
    puts "CANONREF #{f} cites #{h} — that canon section does not exist: " \
         "fix the ref, or add it to `exempt` with the reason it must stay"
  end
end
# Same posture as EXEMPT-DEAD on the `skill #N` stance a hundred lines below —
# and the asymmetry was the finding: that table guards itself, this one did not,
# in the same script. An exemption whose subject is gone protects nothing and
# starts protecting the NEXT phantom that lands on that address. Two ways to die:
# the file stopped citing the ref, or the canon section grew and the ref is no
# longer dangling — both mean the entry must go. Only a SCANNED file can rot;
# under a fixture repo these paths do not exist, and "not applicable" is not
# "rotten" (conflating them would red the self-test on every run).
exempt.each do |f, refs|
  next unless scanned.include?(f)
  (refs - used[f]).each do |r|
    puts "CANONREF-EXEMPT-DEAD #{f} exempts `#{r}`, which is no longer a dangling ref there — " \
         "remove the entry, or it will silently bless the next phantom that takes that address"
  end
end
RUBY
  return 0
}

# ── `skill #N` refs — the address space no §-resolver can see ──────────────
# A skill's numbered gotchas are cited as `frontend #13`, and that is NOT a
# section: every §-resolver parses `NN_NN §Label`, so this form is invisible to
# all four of them BY CONSTRUCTION [DOC-T.60]. Measured 2026-08-04 over the whole
# population (55 refs with an unambiguous target): three were DEAD, all of the
# same shape — `frontend #66` / `#78`, which are LINE numbers, not item numbers
# (the skill defines 17). They resolved to the right text on the day they were
# written, so nothing looked wrong; the first edit above line 66 would have
# silently re-pointed them. The root is measurable and shared with the earlier
# `§Guard-craft #9` miss: `frontend` carries 12 load-bearing paragraphs with no
# number and `ssot-maintenance` 13, so a citation to one degrades either into a
# neighbouring number or into a line number. `backend` has zero unnumbered — and
# zero defects of this class. Ceiling, declared rather than pretended: this
# catches a number OUT OF RANGE, never a number that exists and means something
# else — that half is semantic and only a READ finds it.
skill_item_check() {
  [ -n "$RB" ] || return 0
  [ -d "$REPO/.claude/skills" ] || return 0
  "$RB" - "$MEM_DIR" "$REPO" <<'RUBY'
dir, repo = ARGV
# Resolve against the skills of the repo we were POINTED AT — same hermetic
# posture as canon_section_check: a fixture must never answer with the live tree.
# 🔴 ГЛОБ РОЗШИРЕНО НА ВСІ .md СКІЛА (2026-08-08), і без цього патча операція
# того ж дня осліпила б цей гейт: §Guard-craft виїхала з SKILL.md у
# `guard-craft.md`, тож `ssot-maintenance` віддав би ПОРОЖНІЙ набір пунктів,
# `reject! { items.empty? }` викинув би скіл із мапи — і 65 цитат `#N` у 33
# файлах стали б неперевірюваними МОВЧКИ, при зеленому гейті. Пункти скіла
# тепер збираються з УСІХ його файлів: адреса `skill #N` належить скілу, а не
# конкретному файлу всередині нього.
#
# І номер лишається РЯДКОМ, не Integer: `10a` існує (вставка суфіксом, бо
# перенумерація осиротила б цитати), а `to_i` схлопував би його в `10` — тобто
# цитата `#10a` тихо резолвилась би в ЧУЖИЙ пункт, що гірше за фантом.
skill_files = Dir[File.join(repo, ".claude", "skills", "*", "*.md")]
skills = skill_files.group_by { |p| File.basename(File.dirname(p)) }
                    .transform_values do |paths|
  paths.flat_map { |p| File.readlines(p).filter_map { |l| l[/\A\#{0,4}\s*(\d+[a-z]?)[.)] /, 1] } }.uniq
end
skills.reject! { |_n, items| items.empty? }
exit 0 if skills.empty?

# ── AMBIG · a number that is not an ADDRESS ─────────────────────────────────
# Four skills legitimately carry several numbered sequences (a pipeline, a set
# of gotchas, a recipe), so the same `#N` names two different things and a bare
# citation is ambiguous. The defect is therefore NOT "there is a duplicate" —
# there are 24 and none is a writing error — it is "somebody CITED one without
# saying which sequence". Live yield of the narrow question: zero, which is what
# makes it a battery case; the wide one would be a permanently-red worklist and
# would train the reader to skim the one stance that must stay loud.
#
# 🔴 THE UNIT IS THE FILE, and getting it wrong costs a recount: `ssot-maintenance`
# repeats every one of its numbers across TWO files because `guard-craft.md` is
# the source and the block in SKILL.md is GENERATED from it. Counting per-skill
# calls all 45 of them duplicates and reds the gate on the healthiest invariant
# in the tree. A number is ambiguous only when one FILE uses it twice.
dups = Hash.new { |h, k| h[k] = [] }
skills.each_key do |nm|
  grouped = skill_files.select { |p| File.basename(File.dirname(p)) == nm }
  grouped.each do |p|
    nums = File.readlines(p).filter_map { |l| l[/\A\#{0,4}\s*(\d+[a-z]?)[.)] /, 1] }
    dups[nm] |= nums.tally.select { |_n, c| c > 1 }.keys
  end
end
names = skills.keys.sort_by { |k| -k.length }

# ── HOMOGLYPH · item suffixes must live in ONE alphabet ──────────────────────
# Cyrillic `а` is U+0430 and Latin `a` is U+0061; they are indistinguishable on
# screen, and both classes above are ASCII — so the two halves fail in OPPOSITE
# directions and BOTH are silent. A Cyrillic-suffixed MARKER never enters the
# address space at all (`[a-z]` cannot take it, so the whole line yields
# nothing, and the item has no address). A Cyrillic-suffixed CITATION truncates
# to the bare number, `include?` answers true, and it resolves into the
# NEIGHBOURING item — which is worse than a phantom, because it is a wrong
# address that passes. Measured 2026-08-08: 3 markers and 5 citations live, and
# the one they landed on (`backend #26`) was itself two different items.
# ⚠️ Canon §-numbers are a DIFFERENT address space and are legitimately
# Cyrillic (`04_06 §A.2` rule `10а` is a real heading), so the citation half
# only ever looks INSIDE a `skill #N` window — never at a bare `#N`.
CYR = "[а-я]".freeze
skill_files.sort.each do |p|
  File.readlines(p).each_with_index do |l, i|
    m = l[/\A\#{0,4}\s*(\d+#{CYR})[.)] /, 1]
    next unless m
    puts "HOMOGLYPH  #{p.sub(%r{\A#{Regexp.escape(repo)}/}, '')}:#{i + 1} defines item `#{m}` with a " \
         "CYRILLIC suffix — the collector's `[a-z]` cannot see it, so this item has NO address at all. " \
         "Use the Latin letter"
  end
end

# DECIDED illustrative citations, per FILE and per REF. An illustration of a
# phantom is byte-identical to a phantom, so no anchor can separate them — the
# only honest instrument is a declared exemption. Kept per-ref rather than
# per-file for the reason the sibling gate already learned the hard way: a
# blanket file exemption silently un-checks every OTHER address in that file.
EXEMPT = {
  # The tracker's entry lived here and is GONE — twice over, and both times the
  # detector caught it within minutes of the edit. First when the item was
  # rewritten on closure; then on 2026-08-09 when the item was ARCHIVED and its
  # body — illustration included — collapsed into a §🗄️ row. That is exactly
  # what EXEMPT-DEAD is for: an exemption whose subject vanished stops guarding
  # anything and starts blessing the next phantom to take that address. The
  # entry is removed rather than re-pointed, because the tracker no longer
  # names a phantom at all; if a future item needs to, it declares its own.
  # This file exempts its OWN illustrations, and that is structural rather than
  # untidy: once the perimeter includes `.claude/**`, a gate that documents the
  # phantom class — or fixtures it in the self-test — necessarily writes phantoms
  # into the tree it scans. Widening the perimeter without this entry reds the
  # gate on its own teaching material, which is the fastest way to get a gate
  # disabled. Each ref still stands separately, so an undeclared one still fires.
  ".claude/hooks/memory_gate.sh"      => ["frontend #66", "frontend #78", "frontend #13a"]
}.dup
# Test seam, same shape as MEMORY_GATE_CANONREF_EXEMPT_EXTRA and added for the
# same reason: the EXEMPT-DEAD cases used to fixture their file but borrow the
# LIVE registry's entry, so the day the tracker legitimately stopped naming a
# phantom (its item was archived) both states went red — keeping the entry
# tripped EXEMPT-DEAD, removing it broke the battery. A case must own every
# input it asserts on.
if (extra = ENV["MEMORY_GATE_SKILL_EXEMPT_EXTRA"])
  f, r = extra.split("|", 2)
  (EXEMPT[f] ||= []) << r if f && r
end
EXEMPT.freeze
used_exempt = Hash.new { |h, k| h[k] = [] }
reported = {}

# PERIMETER. Until 2026-08-08 this read `Dir["*.md"]` under MEM_DIR only, i.e.
# it never opened the repo — so a phantom in the tracker, a skill citing another
# skill, and every `skill #N` in `spec/`, `docs/`, `tools/` or `firmware/` were
# unreachable BY CONSTRUCTION while the gate reported green. Measured on the day
# it was widened: 97 citations in memory, 33 more outside it.
sources = Dir.chdir(dir) { Dir["*.md"] }.sort.map { |f| [f, File.join(dir, f)] }
sources += (Dir[File.join(repo, "docs", "**", "*.md")] +
            Dir[File.join(repo, ".claude", "**", "*.{md,sh,rb}")] +
            Dir[File.join(repo, "spec", "**", "*.rb")] +
            Dir[File.join(repo, "{tools,firmware}", "**", "*.{rb,md,c,h}")] +
            Dir[File.join(repo, "*.md")]).sort.uniq
                                         .map { |p| [p.sub(%r{\A#{Regexp.escape(repo)}/}, ""), p] }
                                         # Vendored trees cannot cite our skills and are 96% of the
                                         # glob — scanning them took the gate from 4s to 34s, and a
                                         # PostToolUse hook that slow is a hook someone disables.
                                         # 🔴 Filter the REPO-RELATIVE path, and therefore only AFTER
                                         # the map: an absolute path also carries whatever the PARENT
                                         # dirs happen to be called, so under CI — where the fixture
                                         # repo is `/tmp/tmp.X.repo` — this erased the ENTIRE fixture
                                         # perimeter. The tell was diagnostic: both POSITIVE repo
                                         # cases went silent while every negative one passed
                                         # VACUOUSLY (an empty perimeter is silent for free), so the
                                         # battery read 49/2 rather than collapsing. Green on macOS
                                         # (`mktemp` there ignores TMPDIR and yields /var/folders/…),
                                         # red on Linux — a platform split no local run can see.
                                         .reject { |(rel, _)| rel =~ %r{(\A|/)(extern|vendor|node_modules|site-packages|coverage|tmp)/} }

sources.each do |label, path|
  next unless File.file?(path)
  File.readlines(path).each_with_index do |line, ln|
    # Cheap gate before the O(names) walk: a citation needs a `#` and a digit.
    next unless line.include?("#") && line =~ /#\d/
    names.each do |nm|
      line.to_enum(:scan, /#{Regexp.escape(nm)}/).each do
        pos = Regexp.last_match.begin(0)
        pre  = line[[pos - 2, 0].max...pos].to_s
        post = line[(pos + nm.length), 12].to_s
        # The name must stand in a SKILL CONSTRUCTION, not merely near a `#N`.
        # Mere adjacency was safe while the perimeter was the memory corpus,
        # where these words are almost always skill names; over `docs/` it is
        # not — `deploy`, `frontend`, `backend` are ordinary words, and the
        # tracker's «верифікувати deploy … Pre-Flight #9» read as a citation to
        # a skill that has no item 9. Measured over the whole widened
        # perimeter: this anchor drops both such false positives and loses ZERO
        # real citations, because the repo writes them exactly two ways —
        # `name` in backticks, or `name-скіл gotcha #N`.
        next unless pre.end_with?("`") || post.start_with?("`") ||
                    post =~ /\A[-\s](скіл|скіла|скілу|skill)/i
        # A 40-char window: a citation puts the number right after the name,
        # while a PR/issue number that merely shares the line does not.
        w = line[(pos + nm.length), 40].to_s
        next if w =~ /\b(PR|issue|pull|commit)\b/i
        # Суфікс ловимо разом із числом (`#10a`), інакше цитата на нього
        # зрізалась би до `#10` і резолвилась у сусідній пункт — тихо й хибно.
        w.scan(/#(\d+#{CYR})/) do |(n)|
          puts "HOMOGLYPH  #{label}:#{ln + 1} cites `#{nm} ##{n}` with a CYRILLIC suffix — it truncates " \
               "to `##{n[0..-2]}` and resolves into the NEIGHBOURING item, silently. Use the Latin letter"
        end
        w.scan(/#(\d+[a-z]?)/) do |(n)|
          # A `§Section` between the skill name and the number disambiguates —
          # and that is not a proposal but the convention USAGE already settled
          # on: every live citation to a doubled number already carries one.
          if dups[nm].include?(n) && !w[0...Regexp.last_match.begin(0)].to_s.include?("§")
            if EXEMPT.fetch(label, []).include?("#{nm} ##{n}")
              used_exempt[label] << "#{nm} ##{n}"
            else
              puts "AMBIG      #{label}:#{ln + 1} cites `#{nm} ##{n}`, but that skill uses `#{n}` twice in " \
                   "one file — the number is not an address. Name the sequence: `#{nm} §Section ##{n}`"
            end
          end
          next if skills[nm].include?(n)
          if EXEMPT.fetch(label, []).include?("#{nm} ##{n}")
            used_exempt[label] << "#{nm} ##{n}"
            next
          end
          # One line can hold the same address twice — two mentions of the name,
          # and both 40-char windows reaching both numbers, which reported one
          # finding four times. Noise in a gate's output is what teaches a reader
          # to skim it, so key on the ADDRESS and say it once.
          key = "#{label}:#{ln + 1}:#{nm}:#{n}"
          next if reported.key?(key)
          reported[key] = true
          puts "NUMREF  #{label}:#{ln + 1} cites `#{nm} ##{n}` — that skill defines no item " \
               "##{n} (max ##{skills[nm].max_by { |x| x.to_i }}). A line number is not an address: cite an " \
               "unnumbered paragraph by its opening phrase"
        end
      end
    end
  end
end

# An exemption whose subject is gone stops protecting anything and starts
# protecting the NEXT phantom that lands on that address. So a stale entry is a
# finding, not housekeeping — the exemption list guards itself.
scanned = sources.map(&:first).to_set rescue (require "set"; sources.map(&:first).to_set)
EXEMPT.each do |label, refs|
  # Only a file that was actually SCANNED can make its exemption stale. Under a
  # fixture repo none of these paths exist, and "not applicable" is not "rotten"
  # — conflating them would red the self-test on every run.
  next unless scanned.include?(label)
  (refs - used_exempt[label]).each do |r|
    puts "EXEMPT-DEAD  #{label} exempts `#{r}`, which no longer appears there — remove the entry, " \
         "or it will silently bless the next phantom that takes that address"
  end
end
RUBY
  return 0
}

# Split out of integrity_check so BOTH stances run the same code rather than two
# copies that drift apart unseen — the UNSTRUNG lesson, applied to the two checks
# that were still audit-only. Both fire at the moment of the write that causes
# them: BROKEN is caused by an Edit to MEMORY.md (the most-edited file in the
# corpus), FORMAT by a Write/Edit that drops a frontmatter key. Auditing them
# later means telling the author about a break they can no longer see the cause of.
# ── STALE-STATE ───────────────────────────────────────────────────────────────
# The class no other stance can see, and the reason is its TRIGGER, not its
# shape: memory says «стан звіряй у `00_07` X», the item is later ARCHIVED, and
# the sentence rots — but the edit that rots it happens in the REPO, so the
# PostToolUse hook (which fires on writes into the corpus) never runs at the
# moment of decay. Measured 2026-08-22, the day after four whole families
# (I18N.*, TEST.*, PERF.*, DOC-T.*) went to §🗄️ in two nights: 64 raw hits.
#
# WORKLIST, never a verdict — always exit 0, deliberately OUTSIDE `--audit`.
# Its yield runs to dozens after any archival wave, and a permanently-red
# battery trains the reader to skim the one stance that must stay loud.
#
# The live/archived split comes from `Tracker::Dashboard`, never from a local
# regex: `parse` skips `## 🗄️` by construction and its ITEM_HEAD tolerates the
# STAGE-emoji prefix (`#### 🌿 UNI.13a`) that a bare `[A-Z]` anchor drops
# silently — a hand-rolled matcher got that wrong twice in the session that
# wrote this, in both directions.
#
# DECLARED CEILING, read it before trusting a green run:
#   · Perimeter is the literal `00_07` only. The corpus also routes by BARE ID
#     (`стан → ARCH.85`), which this does not see; that form is rarer for STATE
#     clauses but it exists, so a clean run is not a census.
#   · A PROVENANCE citation of an archived ID is NOT a defect — an instance
#     legitimately names the item it was bought under. Only a clause PROMISING
#     current state is reported, which is why the promise-vocabulary is
#     bilingual: an English-only pattern is blind to half this corpus.
stale_state_check() {
  [ -n "$RB" ] || { echo "DARK  stale_state_check did not run — no usable ruby"; return 0; }
  [ -f "$REPO/lib/tracker/dashboard.rb" ] || { echo "SKIP  no tracker resolver at $REPO/lib/tracker — cannot split live from archived"; return 0; }
  "$RB" - "$MEM_DIR" "$REPO" <<'RUBY'
dir, repo = ARGV
begin
  require File.join(repo, "lib", "tracker", "dashboard")
rescue Exception => e
  puts "DARK  stale_state_check did not run — #{e.class}: #{e.message.lines.first.to_s.strip[0, 120]}"
  exit 0
end
# Overridable so the selftest can pin this against a FIXTURE tracker. Keying the
# cases to real IDs would make them rot the day those items are archived — i.e. the
# very event this detector exists to notice would break its own proof.
md    = File.read(ENV["MEMORY_GATE_TRACKER"].to_s.empty? ? Tracker::Dashboard::DEFAULT_PATH : ENV["MEMORY_GATE_TRACKER"])
live  = Tracker::Dashboard.parse(md).map(&:id).to_set
allid = Tracker::Dashboard.all_item_ids(md).to_set
arch  = allid - live

ID      = /\b([A-Z][A-Za-z0-9]*[.\-][0-9A-Za-z.\-]*[0-9A-Za-z])\b/
# Bilingual on purpose — see the ceiling note above the function.
# 🔴 The lookarounds are LOAD-BEARING, not tidiness. A bare /стан/ matches inside
# «ін-СТАН-с» and «СТАН-дарт» — two of the commonest words in this corpus — and the
# first run of this detector reported 53 hits of which a third were exactly that.
# Same shape as `SMS` matching inside `mechanisMS`: in a corpus whose content IS
# cross-references, the substring and the signal share their characters. Any future
# widening of this pattern gets the same treatment: read the top hits, then trust it.
PROMISE = /(?<!\p{L})[Сс]тан(?:у|і|ом|ів|и)?(?!\p{L})|(?<!\p{L})[Сс]татус(?:у|и|ів)?(?!\p{L})|звіряй|\bStatuses?\b|\bstate\b|\bState\b|verify there|Tracked in/
# A clause that already SAYS the item is closed is doing its job, not rotting.
MARKED  = /🗄️|архівн|archiv|історичн|закрит|closed|вичерпан|retired/i

rows = []
Dir["#{dir}/*.md"].sort.each do |p|
  f = File.basename(p)
  File.foreach(p).with_index(1) do |l, n|
    next unless l.include?("00_07") && l.match?(PROMISE)
    seen = false
    l.enum_for(:scan, "00_07").each do
      s = Regexp.last_match.begin(0)
      frag = l[[0, s - 140].max, 280].to_s
      ids  = frag.scan(ID).flatten.uniq.select { |i| allid.include?(i) }
      next if ids.empty?
      next if ids.any? { |i| live.include?(i) }   # a live heir keeps the route honest
      next if frag.match?(MARKED)
      next if seen
      seen = true
      rows << [f, n, ids.sort, l.strip.gsub(/\s+/, " ")[0, 150]]
    end
  end
end
rows.each { |f, n, ids, t| puts format("STALE-STATE %-40s:%-4d %-22s %s", f, n, ids.join(","), t) }
puts "── #{rows.size} clauses promise CURRENT state at an ID that is archived (live heir = not reported; provenance citation = not reported)"
puts "── fix by NAMING the closure («§🗄️ <date>» / «закрито») or by re-pointing at the live successor — never by deleting the ID: it is the provenance"
RUBY
}

broken_check() {
  local fn
  # Grammar lives in IDX_LINK_RE, not here — see the note at its definition for
  # why a partial widening is worse than none. Deliberately NOT as wide as the
  # string class in strings_check: a markdown link has no prose form to mistake
  # it for, so `[^]]+` there and a slug class here are two different questions,
  # not two settings of one.
  for fn in $(grep -oE "$IDX_LINK_RE" "$IDX" | tr -d ']()' | sort -u); do
    [ -f "$MEM_DIR/$fn" ] || echo "BROKEN  index points at a missing $fn"
  done
  return 0
}

# The KEY and the FILENAME are two spellings of one identity, and only one of
# them is an address: every string resolves through `ls | grep -qix "$l.md"` and
# every index row through `(file.md)`, so the filesystem name is what the corpus
# navigates by, while `name:` is what a reader — and any agent trusting the
# frontmatter — takes the record to BE. Presence was checked; equality was not,
# by anything. The expensive shape is not the cosmetic mismatch but the rename:
# move a file, fix its strings and its index row, and the stale key still names
# a slug that either resolves to NOTHING or, worse, to a NEIGHBOUR — the same
# silent resolution into the wrong home that `skill #N` already paid for one
# address space over. Corpus measured clean when this landed, so it is a battery
# case, not a worklist: the verdict exists to keep a future rename honest.
format_check_one() {
  local fn nm slug; fn=$(basename "$1"); slug=${fn%.md}
  [ "$fn" = "MEMORY.md" ] && return 0
  { grep -q '^name:' "$1" && grep -q 'type:' "$1"; } ||
    echo "FORMAT  $fn lacks name/type frontmatter"
  # First `^name:` is the frontmatter one by position — the block is the head of
  # the file. Quotes are stripped because the standard writes the slug bare and a
  # quoted spelling is the same identity, not a second one.
  nm=$(sed -n 's/^name:[[:space:]]*//p' "$1" | head -1 | tr -d '"'\''[:space:]')
  [ -n "$nm" ] && [ "$nm" != "$slug" ] &&
    echo "NAME    $fn declares name: $nm — strings and the index resolve by FILENAME, so the key is the half that must move (unless you are renaming the file, and then its strings move too)"
  return 0
}

# U+FFFD, the replacement character. In a bilingual corpus a multi-byte word can
# arrive truncated through an editing tool, and the result is a plausible-looking
# word with one glyph replaced — silent, because every other check treats the file
# as valid text and the sentence still scans. Caught twice by eye in one session
# (both times mid-word in Cyrillic) and zero times by any instrument, which is the
# definition of a class that needs one. Runs in both stances: the moment of the
# write is the only moment the author still knows what the word was.
mojibake_check() {
  local fn; fn=$(basename "$1")
  grep -q '�' "$1" &&
    echo "MOJIBAKE $fn carries U+FFFD — a multi-byte character was truncated in an edit; fix the word, do not re-encode the file"
  return 0
}

integrity_check() {
  local fn f
  broken_check
  for f in "$MEM_DIR"/*.md; do
    fn=$(basename "$f"); [ "$fn" = "MEMORY.md" ] && continue
    case $fn in
      # A journal is deliberately absent from the index — it is reached by
      # string. Demanding an index row here would make the gate shout at the
      # very design it exists to protect. Its reachability is NOT unchecked:
      # unstrung_check() owns it, so that both stances run the same test.
      log_*) ;;
      # ORPHAN stays audit-only ON PURPOSE and that exemption is unchanged: it is
      # EXPECTED on a brand-new file, and route_check owns that moment instead.
      *)     grep -q "($fn)" "$IDX" || echo "ORPHAN  $fn is in no index row" ;;
    esac
    format_check_one "$f"
  done
  strings_check
  return 0
}

# The string half, split out so BOTH stances can run it. Keeping it inside
# integrity_check made the PROSE verdict audit-only — a bracketed term stayed
# silent at the very moment it was typed, which is the two-stance divergence
# this file already paid for once (the UNSTRUNG hole). The rest of
# integrity_check cannot join the write stance: ORPHAN is EXPECTED on a
# brand-new file, and route_check owns that moment instead.
strings_check() {
  local l
  # Extraction is deliberately as WIDE as the graph's own parser (oneway_check),
  # because a narrow class does not JUDGE a foreign string — it drops the string
  # before any verdict can run. That is how `[[дім]]` stayed invisible here while
  # oneway_check saw it and silently discarded it as "not present": two grammars
  # over one corpus, and a string that belongs to no detector at all. The dash
  # and A-Z still matter for the same reasons as before (dash-form slug is the
  # broken-link shape; macOS resolves case-only mismatches Linux would not), they
  # are just no longer the FILTER. Widening forces `while read` — a `for l in
  # $(…)` splits multi-word content into phantom strings.
  grep -rhoE '\[\[[^]]+\]\]' "$MEM_DIR"/*.md | sed 's/^\[\[//; s/\]\]$//' | sort -u |
  while IFS= read -r l; do
    case $l in
      # Not slug-shaped => nobody intended a link; this is a prose term someone
      # wrapped in brackets while quoting the convention. A distinct verdict on
      # purpose: DANGLING advises fixing a target, and here the cure is to drop
      # the brackets — the same wrong-advice-on-a-wrong-basis this file guards
      # against elsewhere. The convention itself: quoting the IDEA of a link,
      # never take it in double brackets.
      *[!a-zA-Z0-9_-]*)
        echo "PROSE   [[$l]] is a bracketed term, not a slug — drop the brackets"
        continue ;;
    esac
    # shellcheck disable=SC2010  # the ls|grep IS the test: -qix asks "does any
    # spelling of this name exist", which is precisely what [ -f ] cannot answer
    # on a case-insensitive filesystem. A glob would silently agree with macOS.
    ls "$MEM_DIR" | grep -qix "$l.md" || { echo "DANGLING [[$l]] resolves to nothing"; continue; }
    # The worked example this verdict exists for, and it is not hypothetical:
    # a sentence quoting the convention — "detail belongs in git, not in
    # <double brackets around the word memory>" — parses as a link, and it
    # RESOLVES, but only because macOS folds `memory.md` onto `MEMORY.md`.
    # On a Linux checkout the same corpus is dangling. So a corpus that is
    # green on the author's laptop can be broken everywhere else, which is why
    # CASE is its own verdict rather than a footnote to DANGLING.
    [ -f "$MEM_DIR/$l.md" ] || echo "CASE    [[$l]] only resolves on a case-insensitive filesystem"
  done
  return 0
}

# Routing check for a freshly written file. Deliberately a function: a `case`
# written inline inside $( ) breaks on the bash 3.2 that ships with macOS — the
# `)` closing a pattern is read as closing the substitution. shellcheck parses
# as bash 4+ and stays green on it, so only a real run catches this.
route_check() {
  local bn slug
  bn=$(basename "$1"); slug=${bn%.md}
  case $bn in
    # A journal is reached by string, not by an index row — that is the whole
    # point of it being cheap to append to. So demand the string instead.
    log_*)
      grep -rlq "\[\[$slug\]\]" "$MEM_DIR"/*.md 2>/dev/null ||
        echo "NEW   $bn is a journal nothing links to — hang it off its rule file or it is unreachable"
      ;;
    *)
      # The message used to end "…and give it at least one inbound string" while
      # measuring only the index row — a contract wider than its implementation,
      # which is the shape this gate exists to catch. The string half now has a
      # real owner (unstrung_check, both stances), so this one names its own
      # subject and points at the sibling instead of promising for it.
      grep -q "($bn)" "$IDX" || {
        echo "NEW   $bn is not in the index — route it (own row only if it opens a NEW surface;"
        echo "      otherwise inline it under a hub row). The inbound-string half is NOT measured"
        echo "      here: unstrung_check owns it, and a brand-new file trips it BY DESIGN — write"
        echo "      the router first, which is the same order the 208-session measurement prescribed."
      }
      ;;
  esac
  return 0
}

# --- Self-test ---------------------------------------------------------------
# This gate had no tests, and that is not a tidiness complaint: it has already
# shipped a check that COULD NOT FIRE (overlap_check sat at 167% of the corpus's
# physical maximum and was green on every possible state), and a counting layer
# that silently disagreed with itself (BSD awk under-reported the description sum
# by ~7% while agreeing to the byte on any single file). Both are one failure —
# a green gate proves nothing until something proves the gate can go red.
#
# The constraint that shapes it: a bare "does it fire" battery passes for a gate
# that fires ALWAYS. So case 1 is a HEALTHY corpus that must come back silent,
# and the router case must come back silent too. Positive and negative controls.
#
# Fixture thresholds are derived from the fixture itself, so a case tests its own
# detector rather than the ratchets — except where the ratchet IS the subject.
_st_build() {
  local d=$1
  rm -rf "$d"; mkdir -p "$d"
  # A fixture REPO, because path_check resolves backticked paths against $REPO
  # and the battery never set it: the DEADPATH case was answered by the LIVE
  # tree, so it passed on the accident that nobody had created that filename.
  # A case whose verdict depends on a tree it does not own is not a test of the
  # detector. Two paths, so the fixture can prove both directions.
  rm -rf "$d.repo"; mkdir -p "$d.repo/app/services"
  : >"$d.repo/app/services/live_service.rb"
  # A fixture DOCS tree + a copy of the §-resolver, for the same reason one step
  # on: without them canon_section_check returns 0 for lack of a resolver, and
  # the CANONREF case would "pass" on an ABSENCE — a green that proves nothing.
  # Letter-led headings on purpose: that is the shape 04_06 uses and the one the
  # resolver was blind to until DOC-T.60.
  # Source the resolver relative to THIS SCRIPT, never $REPO: $REPO defaults to a
  # hard-coded developer path that does not exist on a CI runner, so keying the
  # fixture off it made case 10b pass locally and fail in CI — and it failed in
  # the one direction that looks like health, the detector silently going quiet.
  # The script itself lives in the repo, so its own location is the honest root.
  local _root; _root=$(cd "$(dirname "$SELF")/../.." 2>/dev/null && pwd)
  mkdir -p "$d.repo/lib/tracker" "$d.repo/docs"
  [ -f "$_root/lib/tracker/dashboard.rb" ] && cp "$_root/lib/tracker/dashboard.rb" "$d.repo/lib/tracker/"
  cat >"$d.repo/docs/04_06_Testing_Guide_and_Coverage.md" <<'EOF'
# Testing Guide (fixture)

## A.1 Перша секція

Body.

## A.2 Друга секція

Body.
EOF
  # A fixture SKILL tree, for the third address space (NUMREF). Same hermetic
  # reason as the docs tree above: keyed off the live skills, a case would pass
  # or fail on whatever `frontend` happens to contain today. Two numbered items
  # and one UNNUMBERED paragraph — that pairing is the whole point of the class,
  # since it is the unnumbered one that has no address and gets cited by line.
  mkdir -p "$d.repo/.claude/skills/fixtureskill"
  cat >"$d.repo/.claude/skills/fixtureskill/SKILL.md" <<'EOF'
# Fixture skill

1. **First item** — body.
2. **Second item** — body.

🔴 **An unnumbered load-bearing paragraph** — the shape that has no address.
EOF
  cat >"$d/MEMORY.md" <<'EOF'
- [Alpha](feedback_alpha.md) — the naming rule
- [Beta](feedback_beta.md) — the gateway note
EOF
  cat >"$d/feedback_alpha.md" <<'EOF'
---
name: feedback_alpha
description: "Alpha"
metadata:
  type: feedback
---

One word carrying two scales is the quietest defect there is, because both
readings are locally correct and only their meeting point is wrong.

Chronicle of this axis: [[log_gamma]]
EOF
  cat >"$d/feedback_beta.md" <<'EOF'
---
name: feedback_beta
description: "Beta"
metadata:
  type: feedback
---

A gateway counts itself online against an interval it also publishes, so the
two numbers drift apart without either side ever looking wrong on its own.

Kin: [[feedback_alpha]]
EOF
  cat >"$d/log_gamma.md" <<'EOF'
---
name: log_gamma
description: "Gamma"
metadata:
  type: project
---

Chronicle body, dates and numbers live here by design.

Rule home: [[feedback_beta]]
EOF
}

_st_audit() {
  local d=$1; shift
  env MEMORY_GATE_SELFTEST=1 \
      MEMORY_GATE_DIR="$d" \
      MEMORY_GATE_REPO="$d.repo" \
      MEMORY_GATE_IDX_BASELINE="$(wc -c <"$d/MEMORY.md" | tr -d ' ')" \
      MEMORY_GATE_DESC_BASELINE=800 \
      MEMORY_GATE_CORPUS_FLOOR="$(ls "$d"/*.md 2>/dev/null | wc -l | tr -d ' ')" \
      "$@" bash "$SELF" --audit 2>&1
}

# The WRITE stance, which the first version of this battery did not touch at all —
# fifteen cases, all of them --audit. That is a verbatim repeat of the UNSTRUNG
# lesson this file already carries: a check living in one stance only is absent
# from the moment of action, and the write path is where the corpus is actually
# changed. Feeds the real hook contract (stdin JSON) and returns its output.
_st_write() {
  local d=$1 f=$2; shift 2
  printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/%s"}}' "$d" "$f" |
    env MEMORY_GATE_SELFTEST=1 \
        MEMORY_GATE_DIR="$d" \
        MEMORY_GATE_REPO="$d.repo" \
        MEMORY_GATE_IDX_BASELINE="$(wc -c <"$d/MEMORY.md" | tr -d ' ')" \
        MEMORY_GATE_DESC_BASELINE=800 \
        MEMORY_GATE_CORPUS_FLOOR="$(ls "$d"/*.md 2>/dev/null | wc -l | tr -d ' ')" \
        "$@" bash "$SELF" 2>&1
}

selftest() {
  local root d out pass=0 fail=0
  root=$(mktemp -d) || { echo "selftest: cannot mktemp"; return 1; }
  d="$root/mem"

  # $1 = case name, $2 = expect|reject, $3 = token, then extra env for _st_audit.
  # The mutation itself is applied by the caller between _st_build and _st_check.
  _st_check() {
    local name=$1 mode=$2 token=$3; shift 3
    out=$(_st_audit "$d" "$@")
    case $mode in
      expect) printf '%s' "$out" | grep -q "$token" && { pass=$((pass+1)); printf '  ok    %s\n' "$name"; return 0; } ;;
      reject) printf '%s' "$out" | grep -q "$token" || { pass=$((pass+1)); printf '  ok    %s\n' "$name"; return 0; } ;;
    esac
    fail=$((fail+1))
    printf '  FAIL  %s\n         expected to %s /%s/, got:\n%s\n' "$name" "$mode" "$token" "$(printf '%s' "$out" | sed 's/^/         | /')"
    return 1
  }

  # 1. NEGATIVE CONTROL. Without this every other case below is satisfied by a
  #    gate that prints its whole battery unconditionally.
  _st_build "$d"
  _st_check "healthy corpus is silent" expect '^OK — '

  # 2-3. Link integrity, both directions.
  _st_build "$d"; printf '\nSee [[nowhere_at_all]] for more.\n' >>"$d/feedback_beta.md"
  _st_check "DANGLING on an unresolvable [[string]]" expect 'DANGLING'

  _st_build "$d"; printf -- '- [Ghost](feedback_ghost.md) — x\n' >>"$d/MEMORY.md"
  _st_check "BROKEN on an index row pointing at nothing" expect 'BROKEN'

  # 4-5. Registration of a new file.
  _st_build "$d"; printf -- '---\nname: feedback_delta\ndescription: "D"\nmetadata:\n  type: feedback\n---\n\nBody.\n' >"$d/feedback_delta.md"
  _st_check "ORPHAN on a file in no index row" expect 'ORPHAN'

  _st_build "$d"; printf 'No frontmatter at all.\n' >"$d/feedback_delta.md"
  printf -- '- [Delta](feedback_delta.md) — x\n' >>"$d/MEMORY.md"
  _st_check "FORMAT on a file without name/type" expect 'FORMAT'

  # 6. The journal's only lifeline. This one has fired in anger — rewriting a
  #    rule file is exactly when its journal's last string gets severed.
  _st_build "$d"; sed '/log_gamma/d' "$d/feedback_alpha.md" >"$d/.t" && mv "$d/.t" "$d/feedback_alpha.md"
  _st_check "UNSTRUNG on a journal nothing links to" expect 'UNSTRUNG'

  # 6a. The SAME severance on a rule file. The journal-only version was silent
  #     here, and silence is the expensive direction: the file keeps its index
  #     row, so every integrity stance stays green while it stops resonating.
  _st_build "$d"; sed '/feedback_alpha/d' "$d/feedback_beta.md" >"$d/.t" && mv "$d/.t" "$d/feedback_beta.md"
  _st_check "UNSTRUNG on a rule file whose last string was cut" expect 'UNSTRUNG feedback_alpha'

  # 6b. Self-citation is not reachability, and the old bash form could not see it:
  #     it grepped the whole directory, the file included, so naming your own slug
  #     certified you. Reachability is a claim about the REST of the corpus.
  _st_build "$d"; sed '/feedback_alpha/d' "$d/feedback_beta.md" >"$d/.t" && mv "$d/.t" "$d/feedback_beta.md"
  printf '\nSee [[feedback_alpha]] above.\n' >>"$d/feedback_alpha.md"
  _st_check "a file citing its OWN slug is still UNSTRUNG" expect 'UNSTRUNG feedback_alpha'

  # 7. Chronicle inside a rule file, in the bullet costume.
  _st_build "$d"
  { echo; for i in 1 2 3 4; do echo "- 2026-08-0$i something happened that day"; done; } >>"$d/feedback_beta.md"
  _st_check "GENRE on dated blocks in a rule file" expect 'GENRE'

  # 7a. The GENRE line must ARRIVE as a trigger. Its old wording was a sentence
  #     ("chronicle inside a rule file") and the triage that makes cutting safe
  #     lived in a prompt nothing loads automatically — so this wording is not
  #     phrasing, it is the carrier, and it needs a case like any other.
  _st_check "GENRE arrives as a trigger, not a verdict" expect 'not a verdict'

  # 8-9. THE PAIR THAT CARRIES THE MOST. A verbatim rule copied into another file
  #      with no pointer is phase-2 debt; the same copy carrying [[home]] inside
  #      the block is the recipe's prescribed shape and must stay silent. Case 9
  #      is what proves the router test carries weight instead of decorating.
  _st_build "$d"
  printf '\nOne word carrying two scales is the quietest defect there is, because both\nreadings are locally correct and only their meeting point is wrong.\n' >>"$d/feedback_beta.md"
  _st_check "OVERLAP on a duplicated rule with no router" expect 'OVERLAP'

  _st_build "$d"
  printf '\nOne word carrying two scales is the quietest defect there is, because both\nreadings are locally correct and only their meeting point is wrong. Rule lives\nin [[feedback_alpha]].\n' >>"$d/feedback_beta.md"
  _st_check "OVERLAP silent when the copy carries its router" reject 'OVERLAP'

  # 10. A string that resolves to a live file but promises a section that is not there.
  _st_build "$d"; printf '\nMethod: [[feedback_alpha]] §NoSuchSection covers it.\n' >>"$d/feedback_beta.md"
  _st_check "SECREF on a dead §-address" expect 'SECREF'

  # 10b. The canon axis of the same idea [DOC-T.60]: a `NN_NN §X` ref into the
  #      repo's docs, dead. Letter-led deliberately — that is the shape every
  #      gate was blind to until the flip, and the shape an agent quoted back as
  #      canonical after reading it here.
  _st_build "$d"; printf '\nProof form → `04_06 §A.999`.\n' >>"$d/feedback_beta.md"
  _st_check "CANONREF on a dead canon §-address" expect 'CANONREF'

  # 10c. Its negative control. A check that fired on every `NN_NN §X` would pass
  #      10b just as happily, and the corpus is full of legitimately live canon
  #      refs — so the silent half is the half that proves it discriminates.
  _st_build "$d"; printf '\nProof form → `04_06 §A.2`.\n' >>"$d/feedback_beta.md"
  _st_check "CANONREF silent on a live canon §-address" reject 'CANONREF'

  # 10b-i. The exemption seam itself: a DECIDED dead ref must silence CANONREF,
  #        otherwise the curated table is decorative and the gate sits red.
  _st_build "$d"; printf '\nProof form → `04_06 §A.999`.\n' >>"$d/feedback_beta.md"
  _st_check "CANONREF silent while an exemption covers the ref" reject 'CANONREF' \
            MEMORY_GATE_CANONREF_EXEMPT_EXTRA='feedback_beta.md|04_06 §A.999'

  # 10b-ii. And the exemption guards ITSELF. This half was missing while its twin
  #         a hundred lines below (EXEMPT-DEAD on `skill #N`) had it — the same
  #         script, two exemption tables, one law applied. An entry whose subject
  #         is gone protects nothing and starts blessing the next phantom.
  _st_build "$d"
  _st_check "CANONREF-EXEMPT-DEAD when the exempted ref is no longer there" \
            expect 'CANONREF-EXEMPT-DEAD' \
            MEMORY_GATE_CANONREF_EXEMPT_EXTRA='feedback_beta.md|04_06 §A.999'

  # 10b-iii. Negative control that keeps the check honest under a fixture repo:
  #          "not applicable" is not "rotten". Without this the staleness half
  #          would red every run on paths the corpus does not contain.
  _st_build "$d"
  _st_check "CANONREF-EXEMPT-DEAD silent on a file that was never scanned" \
            reject 'CANONREF-EXEMPT-DEAD' \
            MEMORY_GATE_CANONREF_EXEMPT_EXTRA='no_such_file.md|04_06 §A.999'

  # 10d. Third address space [DOC-T.60]: `skill #N`, which NO §-resolver parses.
  #      The live defect was a LINE number worn as an item number, so the fixture
  #      cites one past the skill's last item.
  _st_build "$d"; printf '\nOperational pair → `fixtureskill` #66.\n' >>"$d/feedback_beta.md"
  _st_check "NUMREF on a skill item number out of range" expect 'NUMREF'

  # 10e. Its negative control, and it is load-bearing here: a detector keyed on
  #      `#N` near a skill name would fire on every legitimate gotcha citation in
  #      the corpus, and 55 of them are live. Silence on a real item is the half
  #      that proves it discriminates rather than shouts.
  _st_build "$d"; printf '\nOperational pair → `fixtureskill` #2.\n' >>"$d/feedback_beta.md"
  _st_check "NUMREF silent on a live skill item" reject 'NUMREF'

  # 10f. HOMOGLYPH, MARKER side [DOC-T.62]. A Cyrillic-suffixed item is not a
  #      near-miss — it is absent: the collector's `[a-z]` cannot take U+0430, so
  #      the line yields nothing and the item has no address at all. Three lived
  #      in the tree for weeks under a green gate.
  _st_build "$d"; printf '\n26а. **Cyrillic-suffixed item** — body.\n' >>"$d.repo/.claude/skills/fixtureskill/SKILL.md"
  _st_check "HOMOGLYPH on a Cyrillic item marker" expect 'HOMOGLYPH'

  # 10g. HOMOGLYPH, CITATION side, and it needs its own verdict rather than a
  #      widened class: the suffix is simply left unconsumed, so `#2а` resolves
  #      to item `2` and NUMREF stays green. A wrong address that passes is worse
  #      than a phantom, because nothing ever asks about it again.
  _st_build "$d"; printf '\nOperational pair → `fixtureskill` #2а.\n' >>"$d/feedback_beta.md"
  _st_check "HOMOGLYPH on a Cyrillic item citation" expect 'HOMOGLYPH'

  # 10h. Its negative control, and load-bearing: canon §-numbers are a DIFFERENT
  #      address space and are legitimately Cyrillic (`04_06 §A.2` rule `10а` is
  #      a real heading, cited four times). A detector keyed on the character
  #      rather than on the `skill #N` window would demand renaming live canon.
  _st_build "$d"; printf '\nProof form → `04_06 §A.2`, rule #10а.\n' >>"$d/feedback_beta.md"
  _st_check "HOMOGLYPH silent on a canon §-number with no skill beside it" reject 'HOMOGLYPH'

  # 10j. AMBIG [DOC-T.62]. Four skills legitimately run several numbered
  #      sequences, so `#1` names two different things and a bare citation
  #      resolves into whichever the reader meets first — silently, since the
  #      number DOES exist and NUMREF is green by construction.
  _st_build "$d"
  printf '\n## Second sequence\n\n1. **A step of another list** — body here.\n' >>"$d.repo/.claude/skills/fixtureskill/SKILL.md"
  printf '\nOperational pair → `fixtureskill` #1.\n' >>"$d/feedback_beta.md"
  _st_check "AMBIG on a bare number a skill uses twice in ONE file" expect 'AMBIG'

  # 10k. Its negative control — and this is the shape usage already settled on
  #      by itself: every live citation to a doubled number carries its section.
  _st_build "$d"
  printf '\n## Second sequence\n\n1. **A step of another list** — body here.\n' >>"$d.repo/.claude/skills/fixtureskill/SKILL.md"
  printf '\nOperational pair → `fixtureskill` §Second #1.\n' >>"$d/feedback_beta.md"
  _st_check "AMBIG silent once the citation names the sequence" reject 'AMBIG'

  # 10l. THE UNIT, and it is the case that cost a recount before it existed: a
  #      number repeated across a skill's TWO files is the generated-index shape
  #      (`guard-craft.md` is the source, the block in SKILL.md is produced from
  #      it), i.e. the healthiest invariant in the tree. Counting duplicates
  #      per-SKILL instead of per-FILE calls all 45 of them ambiguous and reds
  #      the gate on correctness itself.
  _st_build "$d"
  printf '1. **First item** — body.\n2. **Second item** — body.\n' >"$d.repo/.claude/skills/fixtureskill/mirror.md"
  printf '\nOperational pair → `fixtureskill` #1.\n' >>"$d/feedback_beta.md"
  _st_check "AMBIG silent on a number mirrored across a skill's files" reject 'AMBIG'

  # 10i. PERIMETER [DOC-T.62, 2026-08-08]. Until this date the citation scan read
  #      the memory dir and nothing else, so a phantom in `docs/`, a skill citing
  #      another skill, and every `skill #N` in specs or firmware were unreachable
  #      BY CONSTRUCTION while the gate reported green. The case lives in the
  #      fixture REPO, not the fixture corpus — that is the whole point of it.
  _st_build "$d"; mkdir -p "$d.repo/docs"
  printf 'Operational pair → `fixtureskill` #66.\n' >"$d.repo/docs/probe.md"
  _st_check "NUMREF reaches a phantom OUTSIDE the memory corpus" expect 'NUMREF'

  # 10j. Its anchor, and the widening is unsafe without it: mere adjacency was
  #      fine while the perimeter was the corpus, where these words are always
  #      skill names — over `docs/` they are ordinary words, and «верифікувати
  #      deploy … Pre-Flight #9» read as a citation to a skill with no item 9.
  #      The name must stand in a skill CONSTRUCTION (backticks, or `-скіл`).
  _st_build "$d"; mkdir -p "$d.repo/docs"
  printf 'верифікувати fixtureskill (крок = Pre-Flight #66 `06_01`)\n' >"$d.repo/docs/probe.md"
  _st_check "NUMREF silent on a bare skill WORD next to a foreign #N" reject 'NUMREF'

  # 10k. EXEMPT-DEAD. An illustration of a phantom is byte-identical to a phantom,
  #      so the only honest instrument is a declared exemption — and an exemption
  #      whose subject is gone stops protecting anything and starts blessing the
  #      NEXT phantom to take that address. Fixture names the real tracker path so
  #      the entry resolves, and omits the ref it exempts.
  _st_build "$d"; mkdir -p "$d.repo/docs"
  printf 'no illustration here\n' >"$d.repo/docs/00_07_Action_Plan_Tracker.md"
  _st_check "EXEMPT-DEAD on an exemption whose subject vanished" expect 'EXEMPT-DEAD' \
            MEMORY_GATE_SKILL_EXEMPT_EXTRA='docs/00_07_Action_Plan_Tracker.md|frontend #13a'

  # 10l. Its negative control, load-bearing twice over: the exemption must still
  #      SUPPRESS (or the widening would simply start shouting at the tracker for
  #      documenting the class), and EXEMPT-DEAD must key on ABSENCE rather than
  #      fire on every listed entry. ⚠️ The fixture has to define `frontend`
  #      itself — the first version of this case did not, so the name was not in
  #      the skill set at all, the citation was never scanned, and the case was
  #      asserting something that could not happen. Caught by the battery.
  _st_build "$d"; mkdir -p "$d.repo/docs" "$d.repo/.claude/skills/frontend"
  printf '# Frontend\n\n1. **One** — body.\n2. **Two** — body.\n' >"$d.repo/.claude/skills/frontend/SKILL.md"
  # ⚠️ One citation per line, deliberately. The first draft also wrote «зрізав до
  # `#13`» inside the same 40-char window, and the case went red — correctly: the
  # exemption is per-REF, so it declined to bless a second, undeclared address.
  # That failure is the per-ref design working, not a fixture nuisance.
  printf 'Виявлено фантомом `frontend #13a` — саме тому виняток оголошено.\n' >"$d.repo/docs/00_07_Action_Plan_Tracker.md"
  _st_check "EXEMPT suppresses the phantom it declares" reject 'NUMREF' \
            MEMORY_GATE_SKILL_EXEMPT_EXTRA='docs/00_07_Action_Plan_Tracker.md|frontend #13a'
  _st_check "EXEMPT-DEAD silent while its subject is present" reject 'EXEMPT-DEAD' \
            MEMORY_GATE_SKILL_EXEMPT_EXTRA='docs/00_07_Action_Plan_Tracker.md|frontend #13a'

  # 11. A backticked path that claims our tree — now answered by the fixture repo.
  _st_build "$d"; printf '\nSee `app/services/no_such_service.rb` for the shape.\n' >>"$d/feedback_beta.md"
  _st_check "DEADPATH on a retracted repo path" expect 'DEADPATH'

  # 11b. Its negative control, absent until the fixture repo existed: a path that
  #      IS there must stay silent. Without this half, a path_check that fired on
  #      every backticked path would have passed case 11 just as happily.
  _st_build "$d"; printf '\nSee `app/services/live_service.rb` for the shape.\n' >>"$d/feedback_beta.md"
  _st_check "DEADPATH silent on a path that exists" reject 'DEADPATH'

  # 11c. THE THIRD STATE [DOC-T.65]. Memory deliberately records a removed file as
  #      part of a decision and says outright that it is gone. The prose cannot
  #      carry that verdict — the measurement in path_check's header is the reason
  #      — so it is DECLARED with a `†` on the closing backtick, and this case is
  #      the one that lets a permanently-red gate go quiet honestly.
  _st_build "$d"; printf '\nThe carrier was `app/services/no_such_service.rb`† — removed, the lesson stands.\n' >>"$d/feedback_beta.md"
  _st_check "DEADPATH silent on a tombstoned dead path" reject 'DEADPATH'

  # 11d. The fourth quadrant — the tombstone's OWN lie, and the reason the marker
  #      is not simply a mute button: a `†` over a file that EXISTS says "removed"
  #      about something present (it came back, or never left). Without this half
  #      the marker would be a permanent silencer that no returning file re-opens.
  _st_build "$d"; printf '\nThe carrier was `app/services/live_service.rb`† — removed, the lesson stands.\n' >>"$d/feedback_beta.md"
  _st_check "TOMBLIVE on a tombstone over a file that exists" expect 'TOMBLIVE'

  # 11e. The marker is per-CITATION — not per-line, not per-file. A bare claim
  #      standing beside an entombed one must still red, and this case exists to
  #      stop a later "simplification" to a line- or file-scoped rule: that is
  #      precisely the shape the corpus measurement rules out (17 live citations
  #      already share a line with retirement wording about something else, so a
  #      line-scoped marker would mute future deaths wholesale).
  _st_build "$d"; printf '\nGone: `app/services/no_such_service.rb`† — yet see `app/services/no_such_service.rb` for the shape.\n' >>"$d/feedback_beta.md"
  _st_check "DEADPATH still fires on a bare citation beside an entombed one" expect 'DEADPATH'

  # 11f. The WRITE stance, because that is where a tombstone is actually typed and
  #      the only stance whose silence nobody ever sees [DOC-T.64]. An --audit-only
  #      proof would leave the moment of action ungoverned by the very branch this
  #      item added; both quadrants ride, so a stance-drift cannot pass one-sided.
  _st_build "$d"; printf '\nThe carrier was `app/services/no_such_service.rb`† — removed.\n' >>"$d/feedback_beta.md"
  out=$(_st_write "$d" feedback_beta.md)
  if printf '%s' "$out" | grep -q 'DEADPATH'; then
    fail=$((fail+1)); printf '  FAIL  %s\n         got: %s\n' "the WRITE stance honours a tombstone too" "$out"
  else
    pass=$((pass+1)); printf '  ok    %s\n' "the WRITE stance honours a tombstone too"
  fi
  _st_build "$d"; printf '\nThe carrier was `app/services/live_service.rb`† — removed.\n' >>"$d/feedback_beta.md"
  out=$(_st_write "$d" feedback_beta.md)
  if printf '%s' "$out" | grep -q 'TOMBLIVE'; then
    pass=$((pass+1)); printf '  ok    %s\n' "the WRITE stance catches a tombstone over a live file"
  else
    fail=$((fail+1)); printf '  FAIL  %s\n         got: %s\n' "the WRITE stance catches a tombstone over a live file" "$out"
  fi

  # 12. The private marker disappearing under a rewrite.
  _st_build "$d"; printf -- '---\nname: user_life_context\ndescription: "L"\nmetadata:\n  type: user\n---\n\nBody.\n' >"$d/user_life_context.md"
  printf -- '- [Life](user_life_context.md) — x\n' >>"$d/MEMORY.md"
  _st_check "PRIVACY on a lost sensitivity marker" expect 'PRIVACY'

  # 13-14. THE FLOOR, and the reason it was added: deletion used to be silent,
  #        and the index ratchet used to answer it with "lock the gain in".
  #        Case 14 pins the wording, because the defect was never the number.
  _st_build "$d"; rm "$d/feedback_beta.md"; sed '/feedback_beta/d' "$d/MEMORY.md" >"$d/.t" && mv "$d/.t" "$d/MEMORY.md"
  _st_check "FLOOR on a deleted file" expect 'FLOOR corpus holds' MEMORY_GATE_CORPUS_FLOOR=4

  # 14 drops the index ROW while the file stays — the shape a hub-inlining pass
  # gets wrong. (An earlier version deleted the file too, and once reach became
  # derived that stopped being eviction at all: both sides fall together, so the
  # honest verdict is loss, which FLOOR owns. The case was measuring the wrong
  # event and only the derivation exposed it.)
  _st_build "$d"; sed '/feedback_beta/d' "$d/MEMORY.md" >"$d/.t" && mv "$d/.t" "$d/MEMORY.md"
  _st_check "eviction is NOT offered as a gain to lock in" reject 'lock the gain in' \
            MEMORY_GATE_IDX_BASELINE=9000

  # 15. The rule-file ceiling, with the cap lowered so the case costs no disk.
  _st_build "$d"; head -c 4000 /dev/zero | tr '\0' 'x' >>"$d/feedback_beta.md"
  _st_check "CAP on a rule file past its ceiling" expect 'CAP  ' MEMORY_GATE_FILE_CAP=3000

  # 15b-15c. THE WARN BAND, which had zero cases while being the band the corpus
  #          actually lives in: five rule-homes sit within 300 B of it, so this is
  #          the branch every phase-2 migration hits first. Two halves, because
  #          "it fires" alone would pass for a detector that fires ALWAYS — and
  #          the positive half pins the WORDING, since the failure this fixes was
  #          a true WARN line that named only the far-off CAP and so read as
  #          headroom while the battery was already red.
  _st_check "WARN names its own EXIT 1, not just the distant cap" expect 'makes --audit EXIT 1' \
            MEMORY_GATE_FILE_WARN=3000 MEMORY_GATE_FILE_CAP=99999
  _st_build "$d"
  _st_check "a file under the working ceiling stays silent" reject 'WARN  ' \
            MEMORY_GATE_FILE_WARN=3000 MEMORY_GATE_FILE_CAP=99999

  # 16-17. THE POSITIVE HALVES of the loss/gain discrimination. Cases 13-14 pinned
  #        that the wrong advice is withheld; nothing pinned that the right advice
  #        is GIVEN, so both branches could be deleted with the battery still green
  #        — the gate-over-an-empty-set class, inside the test for it. Case 17's
  #        branch was worse than untested: under the harness's own DESC_BASELINE
  #        the condition read `tot < 0`, which a byte sum can never satisfy.
  _st_build "$d"; sed '/feedback_beta/d' "$d/MEMORY.md" >"$d/.t" && mv "$d/.t" "$d/MEMORY.md"
  _st_check "eviction IS named when reach drops" expect 'routes to only' MEMORY_GATE_IDX_BASELINE=9000

  _st_build "$d"; rm "$d/feedback_beta.md"; sed '/feedback_beta/d' "$d/MEMORY.md" >"$d/.t" && mv "$d/.t" "$d/MEMORY.md"
  _st_check "DESC drop is blamed on the missing file, not called a gain" expect 'settle FLOOR first' \
            MEMORY_GATE_CORPUS_FLOOR=4 MEMORY_GATE_DESC_BASELINE=1000

  # 17b. The OTHER side of the same fork, and it exists because a mutation slipped
  #      through: breaking `index_links` to a constant 0 left every case green
  #      while turning the gate into a permanent false accusation of eviction.
  #      Cases 14 and 16 both pass under that break — one asserts an absence, the
  #      other asserts the wrong-branch message — so only pinning the HEALTHY
  #      branch makes the discriminator load-bearing in both directions.
  _st_build "$d"
  _st_check "compression with reach intact IS offered as a gain" expect 'lock the gain in' \
            MEMORY_GATE_IDX_BASELINE=9000

  # 18-19. THE WRITE STANCE. Fifteen cases and three mutations all rode --audit,
  #        so the stance this gate exists as — the PostToolUse hook — had zero
  #        coverage, which is the UNSTRUNG lesson repeated verbatim one level up.
  _st_build "$d"
  out=$(_st_write "$d" feedback_alpha.md)
  if [ -z "$out" ]; then pass=$((pass+1)); printf '  ok    %s\n' "write stance is silent on a healthy corpus"
  else fail=$((fail+1)); printf '  FAIL  %s\n%s\n' "write stance is silent on a healthy corpus" "$out"; fi

  _st_build "$d"; rm "$d/feedback_beta.md"; sed '/feedback_beta/d' "$d/MEMORY.md" >"$d/.t" && mv "$d/.t" "$d/MEMORY.md"
  out=$(_st_write "$d" feedback_alpha.md MEMORY_GATE_CORPUS_FLOOR=4)
  if printf '%s' "$out" | grep -q 'FLOOR corpus holds'; then pass=$((pass+1)); printf '  ok    %s\n' "write stance reports a loss at the moment of action"
  else fail=$((fail+1)); printf '  FAIL  %s\n         got: %s\n' "write stance reports a loss at the moment of action" "$out"; fi

  # 19c. STALE-STATE: memory promising CURRENT state at an ARCHIVED item. Pinned
  #      against a FIXTURE tracker (MEMORY_GATE_TRACKER) rather than the live one —
  #      keying it to real IDs would break the proof on the very day an item is
  #      archived, which is the event the detector exists to notice.
  _st_build "$d"
  printf '## §04 · X\n\n#### ZZ.2 — live one\n\n## \xf0\x9f\x97\x84\xef\xb8\x8f Архів\n\n| ID | Пункт | Канон |\n|----|-------|-------|\n| ZZ.1 | closed | 04_01 |\n' >"$root/trk.md"
  printf '\nСтан → `00_07` ZZ.1, механіка → `04_01`.\n' >>"$d/feedback_beta.md"
  out=$(env MEMORY_GATE_DIR="$d" MEMORY_GATE_TRACKER="$root/trk.md" bash "$SELF" --stale-state 2>&1)
  if printf '%s' "$out" | grep -q 'STALE-STATE feedback_beta'; then pass=$((pass+1)); printf '  ok    %s\n' "STALE-STATE on a state-promise at an archived ID"
  else fail=$((fail+1)); printf '  FAIL  %s\n         got: %s\n' "STALE-STATE on a state-promise at an archived ID" "$out"; fi

  # 19d. The half that proves it reads the PROMISE, not the ID: name the closure
  #      and the same clause must go quiet. Without this the detector would pass
  #      just as well if it flagged every mention of an archived item — which is
  #      provenance, the commonest legitimate form in this corpus.
  _st_build "$d"
  printf '\nСтан → `00_07` \xf0\x9f\x97\x84\xef\xb8\x8f ZZ.1 (закрито), механіка → `04_01`.\n' >>"$d/feedback_beta.md"
  out=$(env MEMORY_GATE_DIR="$d" MEMORY_GATE_TRACKER="$root/trk.md" bash "$SELF" --stale-state 2>&1)
  if printf '%s' "$out" | grep -q 'STALE-STATE feedback_beta'; then fail=$((fail+1)); printf '  FAIL  %s\n         got: %s\n' "naming the closure silences it" "$out"
  else pass=$((pass+1)); printf '  ok    %s\n' "naming the closure silences it"; fi

  # 19e. And a LIVE heir in the same clause keeps the route honest — the reader
  #      still has somewhere current to go, so the sentence is not rotten.
  _st_build "$d"
  printf '\nСтан → `00_07` ZZ.1 / ZZ.2, механіка → `04_01`.\n' >>"$d/feedback_beta.md"
  out=$(env MEMORY_GATE_DIR="$d" MEMORY_GATE_TRACKER="$root/trk.md" bash "$SELF" --stale-state 2>&1)
  if printf '%s' "$out" | grep -q 'STALE-STATE feedback_beta'; then fail=$((fail+1)); printf '  FAIL  %s\n         got: %s\n' "a live heir keeps the route honest" "$out"
  else pass=$((pass+1)); printf '  ok    %s\n' "a live heir keeps the route honest"; fi

  # 20. The verdict must not be quietly computed against foreign thresholds.
  _st_build "$d"
  out=$(env MEMORY_GATE_DIR="$d" MEMORY_GATE_CORPUS_FLOOR=1 bash "$SELF" --audit 2>&1)
  if printf '%s' "$out" | grep -q 'OVERRIDE'; then pass=$((pass+1)); printf '  ok    %s\n' "env-overridden thresholds are declared, not silent"
  else fail=$((fail+1)); printf '  FAIL  %s\n         got: %s\n' "env-overridden thresholds are declared, not silent" "$out"; fi

  # 21. ONEWAY fires on the fixture's own provenance string: feedback_alpha
  #     cites [[log_gamma]] and gamma carries nothing back. Asserted at MIN=1,
  #     because the live default of 2 exists to rank a worklist, not to define
  #     the class — a threshold tuned for triage must not be able to hide the
  #     detector's only proof that it works.
  _st_build "$d"
  out=$(env MEMORY_GATE_DIR="$d" MEMORY_GATE_ONEWAY_MIN=1 bash "$SELF" --oneway 2>&1)
  if printf '%s' "$out" | grep -q 'ONEWAY log_gamma'; then pass=$((pass+1)); printf '  ok    %s\n' "one-way provenance string is detected"
  else fail=$((fail+1)); printf '  FAIL  %s\n         got: %s\n' "one-way provenance string is detected" "$out"; fi

  # 22. And the mirror, which is the half that proves it measures RECIPROCITY
  #     rather than merely the presence of a link: give gamma a string back and
  #     the same pair must go quiet. Without this case the detector would pass
  #     just as well if it flagged every citation.
  printf '\nRule for this axis: [[feedback_alpha]]\n' >>"$d/log_gamma.md"
  out=$(env MEMORY_GATE_DIR="$d" MEMORY_GATE_ONEWAY_MIN=1 bash "$SELF" --oneway 2>&1)
  if printf '%s' "$out" | grep -q 'ONEWAY log_gamma'; then fail=$((fail+1)); printf '  FAIL  %s\n         got: %s\n' "a reciprocated pair stops being reported" "$out"
  else pass=$((pass+1)); printf '  ok    %s\n' "a reciprocated pair stops being reported"; fi

  # 22b. The third stance of the same class: a `Related:` line is a PEER
  #      cross-reference, one-way BY DESIGN, and counting it as provenance is
  #      what made this detector overstate three of the four pairs it reported
  #      on the live corpus (2026-08-05). Rebuild so gamma carries nothing back,
  #      then move alpha's SAME citation onto a `Related:` line — the pair must
  #      go quiet, while case 21 proves an ordinary line still fires. The pair
  #      matters more than either half: widen the exclusion until it never fires
  #      and case 21 goes red; drop it entirely and this one does. Written with
  #      a full rewrite rather than `sed -i`, whose flag differs BSD vs GNU and
  #      would pass here and break the CI runner.
  _st_build "$d"
  cat >"$d/feedback_alpha.md" <<'EOF'
---
name: feedback_alpha
description: "Alpha"
metadata:
  type: feedback
---

One word carrying two scales is the quietest defect there is.

Related: [[log_gamma]]
EOF
  out=$(env MEMORY_GATE_DIR="$d" MEMORY_GATE_ONEWAY_MIN=1 bash "$SELF" --oneway 2>&1)
  if printf '%s' "$out" | grep -q 'ONEWAY log_gamma'; then fail=$((fail+1)); printf '  FAIL  %s\n         got: %s\n' "a Related: peer line is not counted as provenance" "$out"
  else pass=$((pass+1)); printf '  ok    %s\n' "a Related: peer line is not counted as provenance"; fi

  # 23-24. THE PAIR FOR THE PROSE VERDICT, and case 24 is the load-bearing half.
  #        A bracketed prose term used to be invisible: the old character class
  #        dropped it before any branch ran, so the corpus carried three of them
  #        under a green gate. Case 24 exists because widening the extractor is
  #        exactly the change that could make the new branch SWALLOW the old one
  #        — a real dangling slug must still read as DANGLING, or the fix trades
  #        one blindness for another and the count alone would never show it.
  _st_build "$d"; printf '\nQuoting the idea of a [[поняття]] is not a link.\n' >>"$d/feedback_beta.md"
  _st_check "PROSE on a bracketed term that was never a slug" expect 'PROSE'

  _st_build "$d"; printf '\nSee [[nowhere_at_all]] for more.\n' >>"$d/feedback_beta.md"
  _st_check "a real dangling slug is NOT reclassified as PROSE" reject 'PROSE'

  # 25. THE WRITE STANCE for the same verdict. Case 23 proves only that --audit
  #     catches it, and audit-only is exactly the divergence this gate already
  #     paid for once: the author is holding the sentence at WRITE time and
  #     nowhere else. Without this case the split into strings_check() would be
  #     refactor-shaped and prove nothing.
  _st_build "$d"; printf '\nQuoting the idea of a [[поняття]] is not a link.\n' >>"$d/feedback_beta.md"
  out=$(_st_write "$d" feedback_beta.md)
  if printf '%s' "$out" | grep -q 'PROSE'; then pass=$((pass+1)); printf '  ok    %s\n' "write stance reports a bracketed term at the moment it is typed"
  else fail=$((fail+1)); printf '  FAIL  %s\n         got: %s\n' "write stance reports a bracketed term at the moment it is typed" "$out"; fi

  # 26. ONE grammar, three consumers — pinned on the HEALTHY fork. A dash-bearing
  #     name is the shape that splits them: widen only integrity_check and the
  #     file reads as a live link there while both reach counters still miss it,
  #     so a corpus that lost nothing gets told it evicted. The verdict to pin is
  #     therefore the ABSENCE of that advice, not the presence of an error — the
  #     failure mode here is a gate lying in the reassuring direction.
  _st_build "$d"
  printf -- '---\nname: feedback_dash-form\ndescription: "D"\nmetadata:\n  type: feedback\n---\n\nBody.\n' >"$d/feedback_dash-form.md"
  printf -- '- [Dash](feedback_dash-form.md) — x\n' >>"$d/MEMORY.md"
  #     The baseline override is what makes it non-vacuous: the eviction ⊥
  #     compression discriminator only runs BELOW the ratchet, so without it the
  #     case never reaches the branch it claims to pin — measured, first draft
  #     survived the mutation and proved nothing.
  _st_check "a dash-bearing name counts as reach in every consumer of the link grammar" \
            expect 'lock the gain in' MEMORY_GATE_IDX_BASELINE=9000

  # 27-29. The three checks that were still audit-only, pinned on the stance that
  #        matters. An inventory of what each stance ACTUALLY runs found these
  #        three missing from the write half — the same divergence the UNSTRUNG
  #        and PROSE cases above already paid for, twice. Each is pinned here so a
  #        future refactor cannot quietly return them to audit-only.
  _st_build "$d"; printf -- '- [Ghost](feedback_ghost.md) — x\n' >>"$d/MEMORY.md"
  out=$(_st_write "$d" MEMORY.md)
  if printf '%s' "$out" | grep -q 'BROKEN'; then pass=$((pass+1)); printf '  ok    %s\n' "write stance reports a broken index row as it is typed"
  else fail=$((fail+1)); printf '  FAIL  %s\n         got: %s\n' "write stance reports a broken index row as it is typed" "$out"; fi

  _st_build "$d"; printf 'No frontmatter at all.\n' >"$d/feedback_beta.md"
  out=$(_st_write "$d" feedback_beta.md)
  if printf '%s' "$out" | grep -q 'FORMAT'; then pass=$((pass+1)); printf '  ok    %s\n' "write stance reports dropped frontmatter at the moment of the write"
  else fail=$((fail+1)); printf '  FAIL  %s\n         got: %s\n' "write stance reports dropped frontmatter at the moment of the write" "$out"; fi

  # Deliberately NOT via _st_write: that helper sets MEMORY_GATE_SELFTEST=1, and
  # override_check exempts itself under it — otherwise every case in this file
  # would trip its own OVERRIDE. So the stance is invoked raw, exactly as the
  # harness invokes it, which is also the only way this case can be honest.
  _st_build "$d"
  out=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/feedback_alpha.md"}}' "$d" |
        env MEMORY_GATE_DIR="$d" MEMORY_GATE_CORPUS_FLOOR=1 bash "$SELF" 2>&1)
  if printf '%s' "$out" | grep -q 'OVERRIDE'; then pass=$((pass+1)); printf '  ok    %s\n' "write stance declares foreign thresholds instead of trusting them"
  else fail=$((fail+1)); printf '  FAIL  %s\n         got: %s\n' "write stance declares foreign thresholds instead of trusting them" "$out"; fi

  # 30a-b. --stops, pinned on the pair that IS the design decision: it must find
  #        an anchored ⛔ ban, and must stay silent on a ⊥ counter-rule heading.
  #        Measured precision for a raw ⊥ sweep is ~15-20% — it marks a deliberate
  #        TRADEOFF, not a ban — so the exclusion is the whole difference between
  #        this mode and a naive grep, and it is the thing a future edit would undo.
  _st_build "$d"
  printf '\n- ⛔ **Відкинуто виміром — не відбудовувати:** диспетчер на HTTP-вісь (0 із 4), ARCH.13.\n' >>"$d/feedback_beta.md"
  printf '\n## ⊥ Контр-правило\n\nСвідома жертва: тут допускається розбіжність, і це не дефект, а дизайн.\n' >>"$d/feedback_beta.md"
  out=$(env MEMORY_GATE_SELFTEST=1 MEMORY_GATE_DIR="$d" bash "$SELF" --stops 2>&1)
  if printf '%s' "$out" | grep -q 'Відкинуто виміром'; then pass=$((pass+1)); printf '  ok    %s\n' "--stops surfaces an anchored ⛔ prohibition"
  else fail=$((fail+1)); printf '  FAIL  %s\n         got: %s\n' "--stops surfaces an anchored ⛔ prohibition" "$out"; fi
  if printf '%s' "$out" | grep -q 'Контр-правило'; then fail=$((fail+1)); printf '  FAIL  %s\n' "--stops stays silent on a ⊥ counter-rule (tradeoff, not a ban)"
  else pass=$((pass+1)); printf '  ok    %s\n' "--stops stays silent on a ⊥ counter-rule (tradeoff, not a ban)"; fi

  # 31-32. A truncated multi-byte character. Positive AND negative control,
  #        because the negative is the load-bearing one here: this corpus is
  #        bilingual and full of glyphs, so a detector that fires on ordinary
  #        Cyrillic would be worse than none.
  _st_build "$d"; printf '\nСлово з обірваним симво\xef\xbf\xbdлом.\n' >>"$d/feedback_beta.md"
  out=$(_st_write "$d" feedback_beta.md)
  if printf '%s' "$out" | grep -q 'MOJIBAKE'; then pass=$((pass+1)); printf '  ok    %s\n' "MOJIBAKE on a truncated multi-byte character, at the write"
  else fail=$((fail+1)); printf '  FAIL  %s\n         got: %s\n' "MOJIBAKE on a truncated multi-byte character, at the write" "$out"; fi

  _st_build "$d"; printf '\nЗвичайна кирилиця, гліфи ⊥ ⛔ 🔴 — усе валідне.\n' >>"$d/feedback_beta.md"
  _st_check "MOJIBAKE silent on healthy Cyrillic and glyphs" reject 'MOJIBAKE'

  # 33-36. THE KEY AGAINST THE FILENAME. Four cases because the failure has two
  #        spellings and the gate has two stances, and the quiet one is the
  #        NEGATIVE: this verdict fires on every file in the corpus on every
  #        write, so a detector that mistook a legal name for a mismatch would be
  #        removed the same day. Case 36 is the one the filesystem hides — macOS
  #        resolves a case-only difference, so the corpus looks consistent while
  #        the key and the address disagree, and only an exact compare sees it.
  _st_build "$d"
  printf -- '---\nname: feedback_wrong_slug\ndescription: "B"\nmetadata:\n  type: feedback\n---\n\nBody.\n' >"$d/feedback_beta.md"
  _st_check "NAME when the frontmatter key and the filename disagree" expect 'NAME    feedback_beta.md'

  _st_build "$d"
  _st_check "NAME silent on a corpus whose keys all match their filenames" reject 'NAME  '

  _st_build "$d"
  printf -- '---\nname: Feedback_Beta\ndescription: "B"\nmetadata:\n  type: feedback\n---\n\nBody.\n' >"$d/feedback_beta.md"
  _st_check "NAME on a case-only difference the filesystem resolves silently" expect 'NAME    feedback_beta.md'

  _st_build "$d"
  printf -- '---\nname: feedback_wrong_slug\ndescription: "B"\nmetadata:\n  type: feedback\n---\n\nBody.\n' >"$d/feedback_beta.md"
  out=$(_st_write "$d" feedback_beta.md)
  if printf '%s' "$out" | grep -q 'NAME'; then pass=$((pass+1)); printf '  ok    %s\n' "write stance reports a key/filename mismatch as it is typed"
  else fail=$((fail+1)); printf '  FAIL  %s\n         got: %s\n' "write stance reports a key/filename mismatch as it is typed" "$out"; fi

  # 32. THE CLASS ITSELF GETS A CARRIER, because writing the rule down failed
  #     three times. "Both stances must run the same battery" has been stated in
  #     the playbook since the UNSTRUNG fix, and the stances diverged again
  #     (PROSE), and again (BROKEN/FORMAT/override). A rule that relapses at a
  #     written form needs an instrument, not a fourth sentence — so the
  #     difference between the two stances is now COMPUTED and compared against
  #     the declared exemptions. Add a check to one stance only, and this reds.
  #
  #     The two exemptions are deliberate, not debt:
  #       overlap_check   — O(n²) over the corpus, and the class it finds
  #                         ACCUMULATES rather than being born in one write.
  #       integrity_check — its parts run in the write stance individually
  #                         (broken_check · format_check_one · strings_check);
  #                         only ORPHAN stays audit-only, because it is EXPECTED
  #                         on a brand-new file and route_check owns that moment.
  #
  #     🔴 And it needed a SECOND half, found by mutating the thing itself: drop
  #     format_check_one from the write stance and this said PARITY-OK. The
  #     exemption is why. integrity_check is exempt BECAUSE its parts ride the
  #     write stance individually — so the diff can only ever look one way (in
  #     audit, absent from write), and the parts, which appear in the write
  #     stance ONLY, are outside the subtraction by construction. The prose above
  #     already names them; naming them was not checking them. So the exemption
  #     now carries its own obligation, and a `defined?`-style guard keeps the
  #     list from rotting into a claim about functions that no longer exist.
  out=$("$RB" - "$SELF" <<'RUBY' 2>/dev/null
src   = File.read(ARGV[0])
audit = src[/^  --audit\)\n(.*?)\n    ;;/m, 1].to_s
write = src[/^  \*\)\n(.*?)\n    ;;/m, 1].to_s
calls = ->(s) { s.scan(/\b([a-z_]+_check)\b/).flatten.uniq }
drift = calls.call(audit) - calls.call(write) - %w[integrity_check overlap_check]

# The exemption's price: each part integrity_check delegates to the write stance
# must actually BE there. Guarded against a stale list — a name here that is no
# longer a function in this file is itself the failure.
parts   = %w[broken_check format_check_one strings_check]
defined = src.scan(/^([a-z_][a-z0-9_]*)\(\) \{/).flatten
ghosts  = parts.reject { |p| defined.include?(p) }
missing = parts.select { |p| defined.include?(p) && write !~ /\b#{Regexp.escape(p)}\b/ }

out = []
out << "PARITY-DRIFT #{drift.sort.join(' ')}" unless drift.empty?
out << "PARITY-GHOST #{ghosts.sort.join(' ')}" unless ghosts.empty?
out << "PARITY-EXEMPT-UNPAID #{missing.sort.join(' ')}" unless missing.empty?
puts out.empty? ? "PARITY-OK" : out.join(" / ")
RUBY
)
  if printf '%s' "$out" | grep -q 'PARITY-OK'; then pass=$((pass+1)); printf '  ok    %s\n' "no check is audit-only without being a declared exemption"
  else fail=$((fail+1)); printf '  FAIL  %s\n         %s — it runs in --audit but not at the moment of the write\n' "no check is audit-only without being a declared exemption" "$out"; fi

  # RUBY RESOLUTION. The class these pin is not "a check is wrong" but "a check
  # did not run and the battery said OK" — the failure that hid for weeks
  # because CI installs `.ruby-version` while the hook takes whatever PATH
  # offers, and PATH went stale on a version bump.
  #
  # 31a. The resolver must reach a usable ruby even with NO rvm on PATH — that
  #      is the live harness condition, not a hypothetical.
  rb_bare=$(env PATH="/usr/bin:/bin" bash -c 'MEMORY_GATE_RUBY=""; '"$(sed -n '/^resolve_ruby()/,/^}/p' "$SELF")"'; resolve_ruby' 2>/dev/null)
  if [ -n "$rb_bare" ] && "$rb_bare" -e 'exit([].filter_map { |x| x } == [] ? 0 : 1)' >/dev/null 2>&1; then
    pass=$((pass+1)); printf '  ok    %s\n' "resolver reaches a usable ruby with no rvm on PATH"
  else
    fail=$((fail+1)); printf '  FAIL  %s\n         got: %s\n' "resolver reaches a usable ruby with no rvm on PATH" "${rb_bare:-<none>}"
  fi

  # 31b. POSITIVE control for the lantern: with every candidate unusable, the
  #      battery must SAY it is dark and red — never print OK on an empty set.
  out=$(env HOME=/nonexistent-home PATH="/usr/bin:/bin" MEMORY_GATE_RUBY=/nonexistent-ruby \
        MEMORY_GATE_DIR="$d" bash "$SELF" --audit 2>&1); rc=$?
  if printf '%s' "$out" | grep -q 'DARK' && [ "$rc" -ne 0 ]; then
    pass=$((pass+1)); printf '  ok    %s\n' "an unusable ruby reds the battery instead of printing OK"
  else
    fail=$((fail+1)); printf '  FAIL  %s\n         rc=%s out=%s\n' "an unusable ruby reds the battery instead of printing OK" "$rc" "$out"
  fi

  # 31c. NEGATIVE control, and it is the load-bearing one: on a healthy corpus
  #      with a usable ruby the word DARK must not appear at all, or 31b would
  #      be satisfied by a gate that cries darkness unconditionally.
  out=$(_st_audit "$d")
  if printf '%s' "$out" | grep -q 'DARK'; then
    fail=$((fail+1)); printf '  FAIL  %s\n         got: %s\n' "a healthy run says nothing about darkness" "$out"
  else
    pass=$((pass+1)); printf '  ok    %s\n' "a healthy run says nothing about darkness"
  fi

  # 31d/31e [DOC-T.64]. The pair above proves the lantern for `--audit` — the stance
  # you invoke deliberately. The WRITE stance is the one wired into settings.json and
  # the only one that fires on every Edit into the corpus, and it had no case on this
  # axis at all: the cured half was hiding the sick one. Same positive/negative shape,
  # because a lantern that lights unconditionally is worth exactly nothing.
  out=$(_st_write "$d" "feedback_alpha.md" MEMORY_GATE_RUBY=/nonexistent-ruby HOME=/nonexistent-home PATH="/usr/bin:/bin")
  if printf '%s' "$out" | grep -q 'DARK'; then
    pass=$((pass+1)); printf '  ok    %s\n' "the WRITE stance says it is dark, not just --audit"
  else
    fail=$((fail+1)); printf '  FAIL  %s\n         got: %s\n' "the WRITE stance says it is dark, not just --audit" "$out"
  fi

  out=$(_st_write "$d" "feedback_alpha.md")
  if printf '%s' "$out" | grep -q 'DARK'; then
    fail=$((fail+1)); printf '  FAIL  %s\n         got: %s\n' "a healthy WRITE says nothing about darkness" "$out"
  else
    pass=$((pass+1)); printf '  ok    %s\n' "a healthy WRITE says nothing about darkness"
  fi

  rm -rf "$root"
  printf 'selftest: %d passed, %d failed\n' "$pass" "$fail"
  [ "$fail" -eq 0 ]
}

case "${1:-}" in
  --selftest) selftest ;;
  --audit)
    # 🔴 The lantern for the whole battery: without a usable ruby, ten of these
    # checks return 0 without running, `out` comes back empty, and the run
    # prints OK. An empty finding-set means "nothing wrong" only when every
    # check actually EXECUTED — so state the precondition before reading it.
    out=$( { [ -n "$RB" ] || rb_dark "ten checks"
             override_check; index_check; desc_check; corpus_floor_check; integrity_check
             unstrung_check; asset_check
             privacy_check; overlap_check; section_ref_check; canon_section_check
             skill_item_check
             for f in "$MEM_DIR"/*.md; do check_file "$f"; path_check "$f"; mojibake_check "$f"; done; } )
    printf '%s\n' "${out:-OK — index within ratchet, corpus intact, no chronicle in a rule file}"
    [ -z "$out" ]
    ;;
  --routes)
    # Єдина перевірка, що дивиться З БОКУ git: скіли/плейбуки/CLAUDE.md
    # адресують memory-файли по імені, і цей напрямок не бачив ніхто —
    # `code_tracker_id_check.rb` знає трекер-ID, а не слаги корпусу, а решта
    # цього файлу живе всередині корпусу. Курація перейменовує й зливає доми,
    # тож рвати маршрут вона може мовчки.
    #
    # СВІДОМО ПОЗА `--audit`, і причина технічна, а не смакова: батарея
    # ганяється селфтестом на ТИМЧАСОВИХ корпусах, де жодного справжнього дому
    # нема, тож усередині неї ця перевірка червонила б усі 41 адреси на кожному
    # прогоні. Те саме, чому її не існує в CI: їй потрібні ОБИДВА корпуси, а на
    # ранері є лише один.
    # 🔴 [DOC-T.64] This line used to read `"${RB:-ruby}"`, i.e. when the fitness
    # probe rejected every candidate it fell back to whatever `ruby` PATH happens to
    # offer — reviving, in one line, the exact "presence, not fitness" defect the
    # probe exists to kill. It also hid from the obvious sweep: a search for the
    # established `[ -n "$RB" ]` idiom does not match a `:-` fallback.
    if [ -z "$RB" ]; then
      rb_dark "the git→memory route check"
      exit 1
    fi
    if [ -f "$REPO/scripts/memory_route_check.rb" ]; then
      MEMORY_GATE_DIR="$MEM_DIR" "$RB" "$REPO/scripts/memory_route_check.rb" "${2:-}"
    else
      echo "SKIP  scripts/memory_route_check.rb is gone — the git→memory direction is unguarded"
      exit 1
    fi
    ;;
  --oneway)
    out=$(oneway_check)
    printf '%s\n' "${out:-OK — no source is cited by ${ONEWAY_MIN}+ homes without pointing back}"
    [ -z "$out" ]
    ;;
  --weight)
    # THE COST LINE NOBODY HAD ENTERED. This corpus polices growth from three
    # directions and loss from one, and it has a floor, a ratchet and a ceiling —
    # but it never once asked what share of itself is about the AGENT rather than
    # about the product, i.e. what the reading tax of its own jurisprudence is.
    # Founder verdict 2026-08-08: "це не аргумент різати — це стаття витрат, якої
    # ми не завели." So this mode PRICES, it does not gate: always exit 0, no
    # threshold, no ratchet. A number that gates would invite cutting the layer
    # that stops lessons being re-bought, which is the opposite of the finding.
    #
    # It reports a BAND, not a figure, and that is the whole point: the split
    # turns on how two 100 kB journals are classified, and a single number would
    # be a verdict dressed as a measurement. Report both bounds or neither.
    #
    # 🔴 DEFECT FOUND IN THIS MODE ON THE DAY IT SHIPPED (2026-08-08), and it is
    # the class this file exists to police. The line said "apparatus in git" while
    # the set was hardcoded to three MEMORY-related files — so it priced the
    # apparatus of the corpus and named it the apparatus of the practice, which is
    # understated 3.7×: the real "how the work is done" layer in git is ~748 kB
    # (15 skills 512 kB + prompts 98 kB + hooks 113 kB + CLAUDE.md 24 kB) against
    # the 200 kB it declared. A measurement whose SCOPE is narrower than its LABEL
    # reads as a fact about the world; that is measurement-substitution, and this
    # mode walked into it while being written to expose it.
    #
    # The fix deliberately does NOT fold the new number into the ratio. That ratio
    # was calibrated against the memory corpus and quoted in DOC-T.62; silently
    # widening its inputs would move a published figure without moving its name —
    # the same defect one level up. So the practice-wide number is reported as its
    # OWN line, and the memory-apparatus subset keeps the ratio it earned.
    "$RB" - "$MEM_DIR" "$REPO" <<'RUBY'
dir, repo = ARGV
sz = Dir["#{dir}/*.md"].to_h { |p| [File.basename(p), File.size(p)] }
# Core META: rules about how the work is done, plus the journals of the method
# itself. Everything else — project state, references, the owner — is DOMAIN.
core = sz.select { |f, _| f.start_with?("feedback_") ||
                          f =~ /\Alog_(memory|perimeter|subagent|cross_ref|measurement)/ }
# Files whose side is a judgement call. Named, so the band is auditable.
swing = sz.select { |f, _| %w[log_stream_scope_axis.md MEMORY.md log_portfolio_surgery.md].include?(f) }
app = { "memory_gate.sh"         => "#{repo}/.claude/hooks/memory_gate.sh",
        "memory_housekeeping.md" => "#{repo}/.claude/prompts/memory_housekeeping.md",
        "memory-maintenance"     => "#{repo}/.claude/skills/memory-maintenance/SKILL.md" }
       .filter_map { |n, p| [n, File.size(p)] if File.exist?(p) }.to_h
tot, c, s, a = sz.values.sum, core.values.sum, swing.values.sum, app.values.sum

# The practice-wide layer, measured rather than assumed. Reported separately from
# `a` on purpose — see the block comment above.
wide = { "skills"  => Dir["#{repo}/.claude/skills/**/*.md"],
         "prompts" => Dir["#{repo}/.claude/prompts/*.md"],
         "hooks"   => Dir["#{repo}/.claude/hooks/*.sh"],
         "CLAUDE"  => ["#{repo}/CLAUDE.md"] }
       .transform_values { |ps| ps.select { |p| File.file?(p) }.sum { |p| File.size(p) } }
biggest = Dir["#{repo}/.claude/skills/**/*.md"].max_by { |p| File.size(p) }

puts "corpus #{tot} B in #{sz.size} files · MEMORY apparatus in git #{a} B (#{app.map { |n, v| "#{n} #{v}" }.join(' · ')})"
puts "core META (feedback_* + method journals) = #{c} B — #{(100.0 * c / tot).round(1)}% of the corpus"
puts
puts "PRACTICE apparatus in git = #{wide.values.sum} B (#{wide.map { |n, v| "#{n} #{v}" }.join(' · ')})"
puts "  — #{(wide.values.sum.to_f / a).round(1)}× the memory-apparatus subset above; NOT folded into the ratio (label ≠ scope, see source)"
puts "  — heaviest single auto-invoked artifact: #{biggest&.sub("#{repo}/", '')} #{biggest ? File.size(biggest) : 0} B" if biggest
puts
[["LOW   swing → DOMAIN", 0], ["HIGH  swing → META", s]].each do |label, extra|
  m = c + extra
  puts format("  %-22s META+apparatus %8d   DOMAIN %8d   → %.2f : 1", label, m + a, tot - m, (m + a).to_f / (tot - m))
end
puts
puts "  swing files (the band's whole width): #{swing.map { |f, v| "#{f} #{v}B" }.join(' · ')}"
puts <<~NOTE

  Read it as a cost line, not a verdict:
    · In EVERY classification the immune system outweighs what it protects.
    · That is not an argument to cut. The same corpus measured ~212 carrier
      firings against ~29 relapses — the meta layer is what stops lessons being
      re-bought, and cutting the index specifically ACCELERATES corpus growth.
    · What this prices is the reading tax of the practice's own law. That was
      once an open ⚖️; it is ANSWERED and archived (the verdict was neither
      "cut" nor "pay forever" but CHANGE THE STORAGE — the corpus is versioned,
      which removes the GROUNDS under growth, not the growth). So this number
      is a standing cost line, not a pending question, and it deliberately
      PRICES without gating: a number that gated here would invite cutting the
      very layer that stops lessons being re-bought.
    · Do not re-route this to 00_07. It said "tracked as a ⚖️ — see 00_07"
      while both items behind it sat in §🗄️ — a self-location claim that rots
      from an edit in ANOTHER file, which is exactly the class this gate exists
      to catch, living inside the gate's own output.
NOTE
RUBY
    ;;
  --stops)
    # WORKLIST, never a verdict — it always exits 0 and is deliberately outside
    # --audit, because its yield runs to hundreds and a permanently-red battery
    # trains the reader to skim the one stance that must stay loud.
    #
    # WHY COMPUTED AND NOT WRITTEN DOWN. The corpus needs this register — an
    # agent starting cold cannot enumerate what has already been decided against,
    # and the price of one miss is a whole session. But it explicitly refused to
    # keep it as prose, for a reason worth repeating: that would be a FOURTH
    # hand-synced mirror, and "a rotten prohibition is worse than an absent one —
    # it blocks correct work with authority". Computed from source on every run,
    # nothing here can go stale by construction.
    #
    # THE PATTERN SET IS MEASURED, not guessed (121 files, 5,483 lines):
    #   · `⊥` is EXCLUDED. It looks like the obvious marker and is not: ~15-20%
    #     precision, because the corpus defines it as a deliberate TRADEOFF, and
    #     most hits are literally `## ⊥ Контр-правило` headings — sections whose
    #     purpose is "here is when the rule does NOT apply", the semantic
    #     opposite of a ban. Every ⊥ that did carry a real ban also tripped one
    #     of the patterns below, so its marginal recall is ~zero and its noise is not.
    #   · `⛔` only when it LEADS a heading or a bullet (~58% precision raw,
    #     ~100% anchored — the false ones are mid-sentence talk ABOUT the
    #     convention: `⛔-мітка`, `у ⛔-списку`).
    #   · `do NOT` / `don't` were absent from the first candidate list and are
    #     among the best (~90%): they carry bans no Ukrainian marker touches.
    "$RB" - "$MEM_DIR" <<'RUBY'
dir = ARGV[0]
BAN  = /(^|[[:space:]])(won.?t-do|відкинуто|відхилено|YAGNI|MUST NOT|do NOT|don't|заборон\w*|не відбудов\w*|не переауд\w*|не пітчити|descope)/i
LEAD = /\A\s*(\#{1,6}\s*|[-*]\s*(\*\*)?)⛔/
ANCH = /\b([A-Z]{2,7}(-[A-Z])?\.\d+[a-z]?)\b|\b20\d\d-\d\d-\d\d\b|\b\d\d-\d\d\b|§|`[^`]+\.(rb|sh|yml|json|md)`/
rows = Hash.new { |h, k| h[k] = [] }
Dir["#{dir}/*.md"].sort.each do |p|
  f = File.basename(p)
  next if f.start_with?("user_")          # private; never in a worklist
  File.readlines(p).each do |l|
    next unless l =~ LEAD || l =~ BAN
    t = l.strip.gsub(/\s+/, " ")
    next if t.length < 25
    rows[f] << [t =~ ANCH ? "ANCHORED  " : "PROSE-ONLY", t[0, 155]]
  end
end
n = rows.values.sum(&:size)
rows.sort.each do |f, rs|
  puts "\n── #{f}  (#{rs.size})"
  rs.each { |tag, t| puts "   #{tag} #{t}" }
end
anch = rows.values.flatten(1).count { |tag, _| tag.start_with?("ANCHORED") }
puts <<~CEIL

  ── #{n} lines across #{rows.size} files · #{anch} carry a checkable anchor (ID/date/§/path), #{n - anch} are bare prose
  ── DECLARED CEILING, read it before trusting the list:
     · This is a FLOOR, not a census. A full READ finds 2-4× more (measured here
       at ~3.2×): the worst prohibitions carry no marker at all, in either language.
     · ~half of even the MARKED lines carry nothing machine-checkable, so their
       freshness is a human question — and ⛔-marks rot FASTER than ordinary prose,
       because they describe the state of OTHER files.
     · ANCHORED means an address exists, NOT that the decision is still current.
       Verify the ID against 00_07's live-vs-archive split before relying on it.
CEIL
RUBY
    ;;
  --stale-state)
    # WORKLIST (always exit 0) — see the block comment on stale_state_check for
    # why this cannot live in --audit and why its trigger is in the REPO, not here.
    stale_state_check
    ;;
  --genre)
    # Journals are exempt HERE too, and the omission was not cosmetic: a journal
    # is the sanctioned home of dated chronicle, so every hit it produced was
    # false BY CONSTRUCTION — and for a while all of them were. A detector whose
    # entire output is known-benign is one a reader learns to skim, which costs
    # exactly the live hit it exists to surface. check_file already skips them;
    # both stances must run the same test (the UNSTRUNG lesson, one level up).
    # Prefix test via parameter expansion, NOT `case`: a `case` inside $( ) is
    # the macOS bash-3.2 trap route_check already documents — and a syntax error
    # here is total, because bash parses the whole file before running any
    # stance, so a broken --genre silently disarms the PostToolUse hook too.
    out=$(for f in "$MEM_DIR"/*.md; do
      bn=$(basename "$f")
      [ "${bn#log_}" != "$bn" ] && continue
      g=$(genre_count "$f"); sum=${g%% *}
      [ "$sum" -ge "$GENRE_MIN" ] && printf '%3d  %-46s %s\n' "$sum" "$bn" "${g##* }"
    done | sort -rn)
    printf '%s\n' "${out:-OK — no dated chronicle in a rule file (journals exempt by design)}"
    [ -z "$out" ]
    ;;
  *)
    input=$(cat)
    fp=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
    case "$fp" in "$MEM_DIR"/*.md) ;; *) exit 0 ;; esac
    msgs=$( { # [DOC-T.64] Same reasoning as the override banner below, one axis over:
              # five of the checks in this stance are ruby-backed and return 0 without
              # running when the toolchain is broken. `--audit` said so; this stance —
              # the one that actually fires on every write — did not, so the half that
              # was cured hid the half that was not.
              [ -n "$RB" ] || rb_dark "five of this stance's checks"
              # A green verdict computed against somebody else's thresholds is the
              # self-attestation this file polices — and it was reported in ONE
              # stance out of four, so an exported MEMORY_GATE_* disarmed the hook
              # silently and permanently. The stance that runs on every write is
              # the one that most needed to say whose thresholds it used.
              override_check
              index_check
              desc_check
              # Loss is silent at the moment of action too — a Write that replaces
              # a corpus is the same tool call as a Write that grows one.
              corpus_floor_check
              # An Edit to MEMORY.md that names a file that does not exist breaks
              # the index AT THIS MOMENT; MEMORY.md is the corpus's most-edited
              # file, so audit-only left the likeliest break silent at its cause.
              broken_check
              # Frontmatter is dropped by the same rewrite that drops anything
              # else — and the author is still holding the file here.
              format_check_one "$fp"
              mojibake_check "$fp"
              check_file "$fp"
              path_check "$fp"
              unstrung_check
              asset_check
              privacy_check
              # Runs on BOTH stances (the UNSTRUNG lesson): severing a section a
              # string points at happens WHILE rewriting, not while auditing. The
              # corpus is at zero here, so any output is this write's own trace.
              section_ref_check
              # Same reasoning one axis over: a canon §-ref is written HERE, and
              # this is the only moment the corpus can be told the address is
              # already dead — nothing downstream ever re-reads it.
              canon_section_check
              # Same moment, third address space: a `skill #N` is written HERE,
              # and no §-resolver downstream will ever look at it.
              skill_item_check
              # A bracketed prose term is TYPED here, and this is the only moment
              # its author is still holding the sentence. Audit-only was the same
              # divergence the checks above exist to avoid — and it is safe to add
              # precisely because this half is at zero on a healthy corpus, so any
              # line is this write's own trace.
              strings_check
              # A brand-new file is where the registry grows. Nothing reads at
              # this moment except the tool call itself, so this is the only
              # place the question "does this fact already have a home?" can be
              # put while it still matters.
              if [ "$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)" = "Write" ] &&
                 [ "$(basename "$fp")" != "MEMORY.md" ]; then
                route_check "$fp"
              fi; } )
    [ -z "$msgs" ] && exit 0
    jq -n --arg ctx "[memory-gate]
$msgs" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$ctx}}'
    ;;
esac
