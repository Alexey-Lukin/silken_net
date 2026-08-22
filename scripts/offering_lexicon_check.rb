#!/usr/bin/env ruby
# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [BIZ.22] Offering-lexicon gate — keeps investment language out of the surfaces a
# customer actually receives (HARD for the storefront, advisory for the code layer).
#
# WHY THIS EXISTS. The 2026-07-25 sweep moved the storefront off investment wording
# (locale labels, manifest, 00_01, 00_04 §1/§4/§5/§10) because the Kik test reads the
# communication delivered to the acquirer, not an identifier buried in a repository.
# That sweep was a HUNT and a FIX with no AUTOMATE: nothing stopped the wording from
# coming back on the next locale, component or README edit. Everywhere else in this
# repo a missing AUTOMATE costs doc drift; here it costs a legal fact, because the
# artefact a regulator or an acquirer's counsel reads is whatever shipped, not the
# tidy state some earlier commit briefly reached. Guard-recipe → 00_06 §3.
#
# TWO TERM SETS, and the split is the whole design.
#
#   OFFERING  — words with no legitimate non-financial reading here (investor,
#               investment, refund, dividend, APY, early-exit fee, and their uk/lt/lv
#               forms). Scanned in every guarded scope.
#   HOMONYM   — words that are financial in a UI label and innocent everywhere else:
#               `yield` (also a materials property and a reaction yield), `portfolio`
#               (also a publication and an R&D portfolio), `ROI` / `payback` /
#               `окупність` (legitimate about OUR OWN unit economics — 00_04 §11-§20 exists to
#               do exactly that — and a problem only about the customer's return, which
#               no regex can tell apart), `funding`, `invested`. Locale VALUES only.
#   HOMONYM_CODE — the same idea narrowed for Ruby source (below).
#
# 🔴 THE FALSE POSITIVE THAT ALMOST KILLED THIS GUARD: `ROI` is a substring of
# **gyroid** — the single most frequent noun in this project. A case-insensitive
# unbounded scan reported the public manifesto as three violations, every one of them
# the word "gyroid". Hence Unicode-letter boundaries on every term, and `ROI` / `APY`
# match case-sensitively. `APR` is deliberately absent: it appears in the maintenance
# locale in a hardware sense whose expansion is documented nowhere, so banning it would
# flag a string nobody can currently justify changing.
#
# TIERS.
#   HARD      — the storefront, verified at zero when this gate landed: locale VALUES,
#               docs/manifest.md, README.md. Drift here fails CI.
#   ADVISORY  — the code layer still carrying the wording while the securities verdict
#               is outstanding (00_07 BIZ.22): response keys in app/controllers/api/**
#               and app/blueprints/**, rendered strings in app/views/**, db/seeds.rb.
#               Reported, never fatal; flip a scope to HARD once it reaches zero.
#
# NAMED CEILINGS [BIZ.22], all three because a regex cannot read intent:
#   (1) HOMONYM terms are gated only inside locale values, so investment framing in
#       engineering prose stays a manual-sweep concern — the ceiling DOC-T.41 already
#       accepted for the manifest, for the same reason.
#   (2) Canon docs under docs/*.md are NOT scanned. They legitimately name the code's
#       own symbols — 05_03 documents `slash(address investor, …)` because that IS the
#       ABI — and a securities-safe rename will carry that prose with it. Scanning them
#       produced ~100 downstream lines per run, which is how an advisory tier becomes
#       noise nobody reads. Canon prose is downstream of the rename, not separate work.
#   (3) Ruby comments are skipped: internal engineering notes are not what a customer
#       receives, and they were a third of the first advisory run.
# The enum value `investor` is likewise out of scope — renaming it is the verdict-gated
# half of BIZ.22, and this gate must not pre-empt a decision that belongs to a lawyer.
#
# EXEMPT: the documents whose job IS to analyse this risk (00_07, docs/protocols/**,
# 00_06, .claude/**) — a securities review forbidden to say "investor" is useless —
# plus CHANGELOG.md, a published historical record; rewriting shipped release notes to
# look cleaner would be dishonest, not compliant.
#
# Pure Ruby, no Rails. Run from repo root:
#   ruby scripts/offering_lexicon_check.rb [--verbose]
# Exit 0 = storefront clean (advisories may still print); exit 1 = HARD drift.

module OfferingLexicon
  ROOT = File.expand_path("..", __dir__)

  module_function

  # Unicode-letter boundary on the left — see the gyroid note above. Stems are
  # intentional (`інвестиц` must catch `інвестиції`), so there is no right boundary;
  # terms that need one spell it out.
  def b(body, ci: true)
    Regexp.new("(?<!\\p{L})(?:#{body})", ci ? Regexp::IGNORECASE : 0)
  end

  OFFERING = {
    b("investor|investment|investing")         => "investor/investment framing",
    b("інвестор|інвестиц|інвестован|інвестув") => "інвестор/інвестиція framing (uk)",
    b("investuot|investicij")                  => "investor framing (lt)",
    b("ieguldīj|ieguldīt|investīcij")           => "investor framing (lv)",
    b("refund|поверненн[яю] кошт")             => "refund promise",
    b("dividend|дивіденд")                     => "dividend",
    b("APY", ci: false)                        => "advertised rate of return",
    b("early[\\s_-]?exit[\\s_-]?fee")          => "early-exit fee framing",
    b("guaranteed return|expected return")     => "promised return"
  }.freeze

  HOMONYM = {
    b("yield")                                  => "`yield` in a user-visible label",
    b("portfolio|портфел")                      => "`portfolio` in a user-visible label",
    b("funding|фінансуванн|finansav|finansēj")  => "`funding` in a user-visible label",
    b("invested|investuo|ieguldīts")            => "`invested` in a user-visible label",
    b("ROI", ci: false)                         => "`ROI` in a user-visible label",
    b("payback|окупн")                          => "`payback` in a user-visible label"
  }.freeze

  # Narrowed for Ruby source. In a locale value "Yield" is always a label; in Ruby,
  # `yield` is the block keyword and `yielder` is an Enumerator::Yielder — scanning the
  # bare stem reported 55 extra lines of pure syntax. Only compound identifiers
  # (`real_yield`, `yield_forecast`) carry the financial sense.
  HOMONYM_CODE = {
    b("[a-z]+_yield|yield_[a-z]+")      => "`yield` in a response key / serialized field",
    b("portfolio")                      => "`portfolio` in a response key / serialized field",
    # `[\s_]` covers both the response key `total_invested:` and the literal
    # "Total Invested" printed into a downloadable CSV/PDF — same statement, two forms.
    b("total[\\s_]invested|amount[\\s_]invested") => "`invested` in a response key / report header",
    b("market_value")                    => "`market value` in a response key / serialized field"
  }.freeze

  HARD_DOCS     = %w[docs/manifest.md README.md].freeze
  ADVISORY_CODE = %w[app/controllers/api/**/*.rb app/blueprints/**/*.rb
                     app/views/**/*.rb app/views/**/*.erb db/seeds.rb].freeze
  RESPONSE_CODE = %w[app/controllers/api/**/*.rb app/blueprints/**/*.rb].freeze

  # Documents that must stay free to name the risk, plus this gate's own files.
  def exempt?(rel)
    rel.start_with?("docs/00_07", "docs/00_06", "docs/protocols/", ".claude/") ||
      rel == "CHANGELOG.md" ||
      rel.include?("offering_lexicon")
  end

  def files(root, *globs)
    globs.flat_map { |g| Dir[File.join(root, g)] }
         .select { |f| File.file?(f) }
         .map { |f| f.sub("#{root}/", "") }
         .reject { |rel| exempt?(rel) }
         .sort
  end

  # A locale line that renders: `key: value` with a non-empty scalar. Only the VALUE is
  # returned — keys are YAML identifiers no user ever sees, and renaming them would move
  # every `t()` call-site for zero legal effect.
  # `chomp` is load-bearing: lines arrive from File.readlines WITH their newline, and an
  # anchored `\z` then matches nothing — which silently killed the entire locale half of
  # this gate while it printed "storefront clean". Caught by the spec, not by a run.
  def locale_value(line)
    return nil unless line.chomp =~ /\A\s*[\w?]+:\s*(\S.*)\z/

    v = Regexp.last_match(1).strip
    (v == "|" || v == ">") ? nil : v
  end

  def numbered(root, rel)
    File.readlines(File.join(root, rel)).each_with_index.map { |l, i| [ i + 1, l ] }
  end

  def code_lines(root, rel)
    numbered(root, rel).reject { |_no, l| l.lstrip.start_with?("#") }
  end

  def scan(rel, numbered_lines, terms)
    numbered_lines.filter_map do |lineno, text|
      re, label = terms.find { |r, _| r.match?(text) }
      "#{rel}:#{lineno} — #{label}: #{text.strip[0, 88]}" if re
    end
  end

  # Returns { hard: [...], advisory: [...] }.
  def audit(root = ROOT)
    hard = []
    advisory = []

    files(root, "config/locales/**/*.yml").each do |rel|
      vals = numbered(root, rel).filter_map { |no, l| (v = locale_value(l)) && [ no, v ] }
      hard.concat(scan(rel, vals, OFFERING), scan(rel, vals, HOMONYM))
    end
    files(root, *HARD_DOCS).each { |rel| hard.concat(scan(rel, numbered(root, rel), OFFERING)) }

    files(root, *ADVISORY_CODE).each { |rel| advisory.concat(scan(rel, code_lines(root, rel), OFFERING)) }
    files(root, *RESPONSE_CODE).each { |rel| advisory.concat(scan(rel, code_lines(root, rel), HOMONYM_CODE)) }

    { hard:, advisory: }
  end
end

if __FILE__ == $PROGRAM_NAME
  r = OfferingLexicon.audit

  unless r[:advisory].empty?
    # Grouped, not per-line: this prints on every CI run, and 44 advisory lines every
    # time is how a report stops being read. One row per file says "still open"; the
    # lines are one --verbose away.
    by_file = r[:advisory].group_by { |a| a[/\A[^:]+/] }
    puts "offering_lexicon_check — ADVISORY: #{r[:advisory].size} hit(s) in " \
         "#{by_file.size} file(s), code layer awaiting the securities verdict (00_07 BIZ.22):"
    by_file.sort.each do |file, hits|
      puts "  · #{file} — #{hits.size} (lines #{hits.map { |h| h[/:(\d+) —/, 1] }.join(',')})"
    end
    r[:advisory].each { |a| puts "    · #{a}" } if ARGV.include?("--verbose")
    puts
  end

  if r[:hard].empty?
    puts "offering_lexicon_check ✓ — storefront clean: locale values, manifest and " \
         "README carry no offering lexicon (BIZ.22)."
    exit 0
  else
    warn "offering_lexicon_check ✗ — offering lexicon returned to a customer-facing surface (BIZ.22):"
    r[:hard].each { |h| warn "  ✗ #{h}" }
    warn "\nThese surfaces are what the acquirer receives. Use service wording " \
         "(contracted / service fee / emission / cluster health) — canon 00_04 §1."
    exit 1
  end
end
