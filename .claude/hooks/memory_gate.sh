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
# Every threshold below is `${ENV:-default}` for ONE reason: --selftest builds a
# five-file fixture corpus, and a constant calibrated against the 1.2 MB live one
# fires on every fixture. The default stays in the file, so a real bump is still
# a git-visible decision — the override exists for the test harness, not for use.
IDX_BASELINE=${MEMORY_GATE_IDX_BASELINE:-23836}
FILE_CAP=${MEMORY_GATE_FILE_CAP:-40960}          # rule-file ceiling
FILE_WARN=${MEMORY_GATE_FILE_WARN:-36000}        # set just under the known relapse file: it regrew 35->53 kB in 18h
GENRE_MIN=${MEMORY_GATE_GENRE_MIN:-4}            # dated blocks, summed across all three costumes

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
CORPUS_FLOOR=${MEMORY_GATE_CORPUS_FLOOR:-123}

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
DESC_BASELINE=${MEMORY_GATE_DESC_BASELINE:-42164}

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
    echo "WARN  $f = ${sz}B (ceiling ${FILE_CAP})"
  fi
  [ "$sum" -ge "$GENRE_MIN" ] &&
    echo "GENRE $f carries $sum dated blocks (h/l/b = $shape) — chronicle inside a rule file"
  return 0
}

# A backticked path that CLAIMS our tree (starts with a real repo root) is a
# checkable assertion; anything else — gem internals (`aasm/base.rb`), a bare
# `queen/main.c` shorthand — is not, and checking those only yields noise the
# gate gets muted for. Measured on the live corpus: 81 claims, 2 dead.
#
# A dead path is one of two things, and the difference is what matters:
# it MOVED (a stale mirror — cheap), or it was RETRACTED — the repo deleted the
# claim as untrue and memory is now the last living copy of a deleted untruth.
# Only the commit body can tell them apart, so the message says so.
PATH_ROOTS='app|lib|scripts|docs|firmware|contracts|config|db|spec|tools|bin|deploy|terraform|subgraph|\.claude|\.github'

path_check() {
  local f=$1 p
  for p in $(grep -ohE '`('"$PATH_ROOTS"')/[a-zA-Z0-9_./-]+\.[a-z]{1,4}`' "$f" 2>/dev/null |
               tr -d '`' | sort -u); do
    [ -e "$REPO/$p" ] || echo "DEADPATH $(basename "$f") cites \`$p\` — gone from the repo; \`git log --diff-filter=D -- $p\` says whether it MOVED or was RETRACTED"
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
  command -v ruby >/dev/null 2>&1 || return 0
  tot=$(ruby - "$MEM_DIR" <<'RUBY'
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
  command -v ruby >/dev/null 2>&1 || return 0
  ruby - "$MEM_DIR" "$OVERLAP_COEF" "$OVERLAP_MIN_SHINGLES" <<'RUBY'
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
index_links() { grep -oE '\]\([a-z0-9_]+\.md\)' "$IDX" | sort -u | wc -l | tr -d ' '; }

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
  n=$(grep -cE '^[[:space:]]*- .*\]\([a-z0-9_]+\.md\)' "$IDX")
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
journals_reachable() {
  local f s
  for f in "$MEM_DIR"/log_*.md; do
    [ -e "$f" ] || continue
    s=$(basename "$f" .md)
    grep -rlq "\[\[$s\]\]" "$MEM_DIR"/*.md 2>/dev/null ||
      echo "UNSTRUNG $(basename "$f") is a journal nothing links to — it is unreachable"
  done
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
  command -v ruby >/dev/null 2>&1 || return 0
  ruby - "$MEM_DIR" <<'RUBY'
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
  command -v ruby >/dev/null 2>&1 || return 0
  [ -f "$REPO/lib/tracker/dashboard.rb" ] || return 0
  ruby - "$MEM_DIR" "$REPO" <<'RUBY'
dir, repo = ARGV
begin
  require File.join(repo, "lib", "tracker", "dashboard")
rescue Exception
  exit 0   # no repo / unloadable resolver → silent, never a false alarm
end
# Curated exemptions, same posture as the SPDX gate's DENY list: a DECIDED case
# is recorded with its reason so the gate never sits permanently red on it, and
# the detector stays live for every new ref. Keyed per file, so an exemption
# never blinds a whole file the way a path-level EXEMPT would.
exempt = {
  # The renumber-drift teaching case: `§749` is a LINE number written as a
  # section — citing it IS the lesson. `code_doc_section_refs.rb` exempts the
  # ssot-maintenance skill for this same ref, for this same reason.
  "project_ssot_campaign_history.md" => ["05_03 §749"]
}
# Resolve against the docs of the repo we were POINTED AT, never the one the
# resolver happens to sit in — otherwise the fixture would silently answer with
# the live tree, which is exactly the non-hermetic shape DEADPATH just outgrew.
docs = File.join(repo, "docs")
exit 0 unless Dir.exist?(docs)
Dir.chdir(dir) { Dir["*.md"] }.sort.each do |f|
  Tracker::Dashboard.file_section_dangling_refs(File.read(File.join(dir, f)), docs).each do |h|
    ref = h.to_s.delete("`")
    next if exempt.fetch(f, []).any? { |e| ref.include?(e) }
    puts "CANONREF #{f} cites #{h} — that canon section does not exist: " \
         "fix the ref, or add it to `exempt` with the reason it must stay"
  end
end
RUBY
  return 0
}

integrity_check() {
  local fn f l
  for fn in $(grep -oE '\]\([a-z0-9_]+\.md\)' "$IDX" | tr -d ']()' | sort -u); do
    [ -f "$MEM_DIR/$fn" ] || echo "BROKEN  index points at a missing $fn"
  done
  for f in "$MEM_DIR"/*.md; do
    fn=$(basename "$f"); [ "$fn" = "MEMORY.md" ] && continue
    case $fn in
      # A journal is deliberately absent from the index — it is reached by
      # string. Demanding an index row here would make the gate shout at the
      # very design it exists to protect. Its reachability is NOT unchecked:
      # journals_reachable() owns it, so that both stances run the same test.
      log_*) ;;
      *)     grep -q "($fn)" "$IDX" || echo "ORPHAN  $fn is in no index row" ;;
    esac
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
      grep -q "($bn)" "$IDX" || {
        echo "NEW   $bn is not in the index — route it (own row only if it opens a NEW surface;"
        echo "      otherwise inline it under a hub row) and give it at least one inbound [[string]]"
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
EOF
  cat >"$d/log_gamma.md" <<'EOF'
---
name: log_gamma
description: "Gamma"
metadata:
  type: project
---

Chronicle body, dates and numbers live here by design.
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

  # 7. Chronicle inside a rule file, in the bullet costume.
  _st_build "$d"
  { echo; for i in 1 2 3 4; do echo "- 2026-08-0$i something happened that day"; done; } >>"$d/feedback_beta.md"
  _st_check "GENRE on dated blocks in a rule file" expect 'GENRE'

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

  # 11. A backticked path that claims our tree — now answered by the fixture repo.
  _st_build "$d"; printf '\nSee `app/services/no_such_service.rb` for the shape.\n' >>"$d/feedback_beta.md"
  _st_check "DEADPATH on a retracted repo path" expect 'DEADPATH'

  # 11b. Its negative control, absent until the fixture repo existed: a path that
  #      IS there must stay silent. Without this half, a path_check that fired on
  #      every backticked path would have passed case 11 just as happily.
  _st_build "$d"; printf '\nSee `app/services/live_service.rb` for the shape.\n' >>"$d/feedback_beta.md"
  _st_check "DEADPATH silent on a path that exists" reject 'DEADPATH'

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

  # 20. The verdict must not be quietly computed against foreign thresholds.
  _st_build "$d"
  out=$(env MEMORY_GATE_DIR="$d" MEMORY_GATE_CORPUS_FLOOR=1 bash "$SELF" --audit 2>&1)
  if printf '%s' "$out" | grep -q 'OVERRIDE'; then pass=$((pass+1)); printf '  ok    %s\n' "env-overridden thresholds are declared, not silent"
  else fail=$((fail+1)); printf '  FAIL  %s\n         got: %s\n' "env-overridden thresholds are declared, not silent" "$out"; fi

  rm -rf "$root"
  printf 'selftest: %d passed, %d failed\n' "$pass" "$fail"
  [ "$fail" -eq 0 ]
}

case "${1:-}" in
  --selftest) selftest ;;
  --audit)
    out=$( { override_check; index_check; desc_check; corpus_floor_check; integrity_check
             journals_reachable; asset_check
             privacy_check; overlap_check; section_ref_check; canon_section_check
             for f in "$MEM_DIR"/*.md; do check_file "$f"; path_check "$f"; done; } )
    printf '%s\n' "${out:-OK — index within ratchet, corpus intact, no chronicle in a rule file}"
    [ -z "$out" ]
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
    msgs=$( { index_check
              desc_check
              # Loss is silent at the moment of action too — a Write that replaces
              # a corpus is the same tool call as a Write that grows one.
              corpus_floor_check
              check_file "$fp"
              path_check "$fp"
              journals_reachable
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
