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
IDX_BASELINE=23836
FILE_CAP=40960          # rule-file ceiling
FILE_WARN=36000        # set just under the known relapse file: it regrew 35->53 kB in 18h
GENRE_MIN=4             # dated blocks, summed across all three costumes

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
DESC_BASELINE=42164

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
  [ "$tot" -lt $((DESC_BASELINE - 800)) ] &&
    echo "DESC  description layer = ${tot}B, well below the ${DESC_BASELINE}B ratchet — lower DESC_BASELINE here to lock the gain in"
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

case "${1:-}" in
  --audit)
    out=$( { index_check; desc_check; integrity_check; journals_reachable; asset_check
             privacy_check; overlap_check; section_ref_check
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
              check_file "$fp"
              path_check "$fp"
              journals_reachable
              asset_check
              privacy_check
              # Runs on BOTH stances (the UNSTRUNG lesson): severing a section a
              # string points at happens WHILE rewriting, not while auditing. The
              # corpus is at zero here, so any output is this write's own trace.
              section_ref_check
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
