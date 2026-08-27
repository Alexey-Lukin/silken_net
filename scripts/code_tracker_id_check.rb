#!/usr/bin/env ruby
# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Phantom tracker-ID gate: code ⟷ 00_07 ID-set.
#
# Code comments (and workflow/config text) cite 00_07 tracker IDs — `[FW.2]`,
# `target ARCH.10`, `→ 00_07 SEC.20` — but nothing validated that the cited ID
# EXISTS: tracker:check resolves refs INSIDE 00_07, and the code trees were a
# blind spot. Proof-case (2026-07-16, found by hand): firmware/queen/main.c
# cited the phantom `ARCH.35-Q2Q` (the real item is ARCH.10) and no gate
# blinked. This is protocols_ref_check's sibling for the ID namespace.
#
# Mechanics: the ID-set = Tracker::Dashboard.all_item_ids (every #### heading
# + table-row first-cell across ALL sections incl. 📌 Backlog / 🗄️ Архів —
# archived IDs stay citable). Prefix families (ARCH, FW, DOC-T, …) are DERIVED
# from that set, so a token like `PM2.5` or `TLS1.2` whose prefix is not a
# tracker family is never considered. A hyphen-tail is kept only while it
# stays UPPERCASE/digits (`ARCH.35-Q2Q` → one token, flagged) — a lowercase
# tail is prose (`FW.2-gated` → `FW.2`, resolves). CHEM.N notes are bullets,
# not items, so the CHEM family is absent here by construction — it has its
# own guard (chem_note_ref_violations).
#
# Pure Ruby, no Rails. Run from repo root: ruby scripts/code_tracker_id_check.rb
# Exit 0 = every cited ID resolves; exit 1 = phantom IDs (lists them).

require_relative "../lib/tracker/dashboard"

ROOT  = File.expand_path("..", __dir__)
# `deploy` + `terraform` + `subgraph` joined 2026-08-27 (DOC-T.92 · OPS.36). All three
# cite tracker IDs in prose a human reads at 3am — the Grafana alert `description:`
# fields route the on-call to an item by ID — and none was supervised by anything.
# Price was MEASURED before enabling (00_05 §5): zero hits, so the widening is free.
# ⛔ `docs/` deliberately stays OUT, and that is a MEASUREMENT, not an omission: the
# same probe over `docs/**` returned 36 candidates (retired facets, ranges the split
# does not reach, historical mentions). The tracker item that prescribed this leg read
# «ціна = 0», but that zero belongs to the LINK form `[`ID`](00_07…)` — which is gated
# on the OTHER side now (`Tracker::Dashboard::INBOUND_LABEL_REF_RE`) — never to every
# ID-shaped token in canon prose. Widening here is work-then-gate, not gate.
TREES = %w[app lib firmware contracts spec scripts tools bin config db deploy terraform subgraph .claude].freeze
EXTS  = "{rb,c,h,sol,py,sh,rake,erb,yml,yaml,md,json}"

# The tracker parser + its spec fixtures legitimately carry ID-shaped tokens
# that exercise the resolver; this script itself cites the proof-case phantom;
# vendored/build trees are not our prose.
#
# CHANGELOG.md is NOT exempt as a file — it is release-please-generated, so a
# stale ID there cannot be "fixed" in place (rewriting it would falsify
# history), but it is the best index of which IDs ever existed: exempting the
# file hid E.28, the twin of the OPS.8 orphan (same prune commit, same "zero
# inbound refs" claim). So it reports separately instead of gating.
# `spec/quality/tracker_id_range_split_spec.rb` pins THIS script's range-split
# and must therefore spell real-looking IDs (`DOC-T.5`, `UI.2-S`, `ARCH.35-Q2Q`)
# plus deliberate phantoms as TEST DATA — the same reason `spec/lib/` is exempt.
# Named per-file rather than blanketing `spec/quality/`: a blanket would silently
# drop every other quality spec out of this gate's reach.
#
# 🔴 `node_modules` is exempted as a CLASS (any depth), never per-directory: it is
# gitignored, so a per-name list makes the gate scan a tree LOCALLY that does not exist
# in CI — the "on the FS, not in git" divergence. Measured when `subgraph/` joined
# TREES: 6873 vendored files entered the scan from one gitignored directory, i.e. the
# local run and the CI run were grading different trees while both printed green.
EXEMPT = %r{\A(?:lib/tracker/dashboard\.rb|spec/lib/|spec/quality/tracker_id_range_split_spec\.rb|scripts/code_tracker_id_check\.rb|[^\n]*node_modules/|contracts/(?:out|cache|lib)/|firmware/extern/|tools/[^/]+/venv/)}
ADVISORY_ONLY = %r{\ACHANGELOG\.md:}

# ID-shaped tokens that are NOT tracker refs: external standards etc.
KNOWN_BENIGN = %w[E.164].to_set # ITU-T phone-number format

# ID-shaped token: family prefix (may be hyphen-joined like DOC-T, PUMA-IPV6)
# + `.` OR `-` + digit tail; optional UPPERCASE hyphen-segments (facets) stay
# part of the token; `/`-joined digit families (`ARCH.64/65`) expand below.
#
# The separator class MUST match Tracker::Dashboard's own ID shape (`[.\-]`):
# an earlier `\.\d` here made the gate structurally blind to every
# hyphen-numbered ID — `SLASH-1` (cited in 33 files!), `PUMA-IPV6-1`,
# `PUMA-RACK-1` were never even candidates. Close-review 2026-07-16.
#
# Known ceiling: dotless word-IDs (`SE050-MIGRATION`, `OS-RECOMPUTE`) are
# shape-identical to ordinary SHOUTED prose, so they are matched only when
# they appear verbatim in the ID-set (below) — never as phantom candidates.
TOKEN_RE = %r{(?<![A-Za-z0-9_])[A-Z][A-Za-z0-9]*(?:-[A-Z][A-Za-z0-9]*)*[.\-]\d[0-9A-Za-z.]*(?:-[A-Z0-9.]+)*(?:/\d+)*}

tracker_md     = File.read(Tracker::Dashboard::DEFAULT_PATH)
ids            = Tracker::Dashboard.all_item_ids(tracker_md).to_set
facet_evidence = Tracker::Dashboard.item_body_text(tracker_md)
families       = ids.filter_map { |id| id[/\A[A-Z][A-Za-z0-9]*(?:-[A-Z][A-Za-z0-9]*)*(?=[.\-]\d)/] }.to_set

# A token resolves if it IS an item ID, or if it is a FACET of one: `FW.20-S2`,
# `ARCH.41-B`, `HW.3.IS` — a real item (the base) plus a suffix declared
# verbatim in a LIVE `####` item body. Both halves are required:
#
#   * base must be a real item → a bare ID with no home (`E.2`) is a phantom
#     even though 00_07 happens to name it in someone else's prose (it did:
#     inside SEC.1's body). Close-review 2026-07-16 caught exactly this — a
#     plain verbatim fallback let the 14th orphan through.
#   * facet must be declared → `ARCH.35-Q2Q` fails (real base, invented
#     suffix: 00_07 never wrote that compound). That is the proof-case.
#
# Evidence scope = item_body_text (#### blocks only), NOT the whole tracker
# (DOC-T.42 ①): a retired sub-ID is verbatim-quoted by the very §🗄️/DOC-T
# table-row that documents its retirement, so a whole-file match keeps the
# dead ID "resolvable" forever — the necrology immunises the phantom (8
# HW.1-family refs survived 11 passes on exactly this trap).
# ⚠️ RESIDUAL CEILING, and the narrowing above does not remove it (recorded here
# 2026-08-10; it lived only in the 00_06 §3 row): a necrology written INSIDE a
# live `####` body still immunises. The form cannot see semantics — "retired,
# do not cite" and a live declaration are the same bytes to it — so the fix that
# closed the dominant, TABLE-shaped case leaves the in-body one open by design.
# Only a reading catches it; do not read this gate's green as coverage of that.
def resolves?(tok, ids, facet_evidence)
  return true if ids.include?(tok)

  base = tok[/\A[A-Z][A-Za-z0-9]*(?:-[A-Z][A-Za-z0-9]*)*\.\d+/]
  return false unless base && base != tok && ids.include?(base)

  facet_evidence.match?(/(?<![A-Za-z0-9_])#{Regexp.escape(tok)}(?![0-9A-Za-z])/)
end

files = TREES.flat_map { |t| Dir[File.join(ROOT, t, "**", "*.#{EXTS}")] } +
        Dir[File.join(ROOT, ".github", "**", "*")] +
        Dir[File.join(ROOT, "*.md")]
files = files.select { |p| File.file?(p) }
             .map { |f| f.sub("#{ROOT}/", "") }.uniq.reject { |rel| rel =~ EXEMPT }.sort

phantoms = files.flat_map do |rel|
  text = begin
    File.read(File.join(ROOT, rel))
  rescue ArgumentError
    next [] # non-UTF-8 / binary
  end
  text.each_line.with_index(1).flat_map do |line, n|
    line.scan(TOKEN_RE).flat_map do |tok|
      tok = tok.sub(/[.\-]+\z/, "") # sentence punctuation / dangling hyphen
      # An ID-shaped hyphen segment is a RANGE (`E.20-E.34`) — check each end.
      # DOTTED both sides on purpose: a `[.\-]\d` lookahead here would slice
      # fixture strings (`TEST-DEVICE-001` → `TEST` + `DEVICE-001`) into
      # phantom halves.
      #
      # 🔴 The LEFT side needs the same discipline, and until 2026-08-09 it had
      # none: with only a lookahead, the hyphen INSIDE a family prefix read as a
      # range boundary, so `DOC-T.62` split into `DOC` + `T.62` — neither of
      # which is a family, so `families.include?` dropped both and the citation
      # was never checked at all. Measured: 57 of the tracker's 494 IDs are
      # `DOC-T.*` and 201 citations of them sit inside this gate's own trees, so
      # the whole SSOT-tooling family was invisible — a phantom `DOC-T.999`
      # passed while `SEC.999`/`ARCH.999`/`UI.999` reddened (mutation-verified
      # in both directions). This is the SAME blindness the TOKEN_RE comment
      # above records fixing for `SLASH-1`: it was repaired where the token is
      # RECOGNISED and left standing forty lines down where it is SPLIT — the
      # half-fix shape, where the healthy half is what hides the sick one.
      # The lookbehind requires a COMPLETED id (`…\d`) before the hyphen, so a
      # real range still splits and a prefix-internal hyphen never does; the
      # lookahead reuses the same prefix shape as `families` rather than a
      # narrower hand-rolled one, or `DOC-T.62-DOC-T.63` would stop splitting.
      parts = tok.split(/(?<=\d)-(?=[A-Z][A-Za-z0-9]*(?:-[A-Z][A-Za-z0-9]*)*[.\-]\d)/)
      # `/`-joined digit family (`ARCH.64/65`, `INF.3/4/6`) — every member is a
      # ref; the same idiom Tracker::Dashboard.expand_prose_ids already handles.
      parts = parts.flat_map do |p|
        segs = p.split("/")
        next [ p ] if segs.one?

        prefix = segs.first[/\A[A-Z][A-Za-z0-9]*(?:-[A-Z][A-Za-z0-9]*)*[.\-]/]
        prefix ? segs.map { |s| s.match?(/\A\d/) ? "#{prefix}#{s}" : s } : [ p ]
      end
      parts.filter_map do |part|
        next unless families.include?(part[/\A[A-Z][A-Za-z0-9]*(?:-[A-Z][A-Za-z0-9]*)*/])
        next if KNOWN_BENIGN.include?(part) || resolves?(part, ids, facet_evidence)

        "#{rel}:#{n}: `#{part}` не резолвиться в 00_07 (фантом-ID або renamed)"
      end
    end
  end
end.uniq

gating, advisory = phantoms.partition { |p| !p.match?(ADVISORY_ONLY) }

unless advisory.empty?
  puts "code_tracker_id_check — CHANGELOG cites #{advisory.size} ID(s) with no 00_07 home " \
       "(advisory: generated file, do not rewrite; give the ID a §🗄️ row if it deserves one):"
  advisory.sort.each { |a| puts "  · #{a}" }
end

if gating.empty?
  puts "code_tracker_id_check ✓ — #{files.size} files scanned; every cited tracker-ID " \
       "resolves against 00_07 (#{ids.size} IDs, #{families.size} families)"
  exit 0
else
  warn "code_tracker_id_check ✗ — phantom tracker-IDs cited in code (00_07 has no such item):"
  gating.sort.each { |p| warn "  · #{p}" }
  exit 1
end
