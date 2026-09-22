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
#               `окупність` (legitimate about OUR OWN unit economics — that subject
#               lives in 02_06; the 00_04 section range this line used to cite died when
#               the unit economics moved out — and a problem only about the customer's
#               return, which no regex can tell apart), `funding`, `invested`.
#               Locale VALUES only.
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
#   HARD (code) — OFFERING terms across app/controllers/api/**, app/blueprints/**,
#               app/views/**, db/seeds.rb. ⚖️ **Flipped advisory → HARD 2026-09-22**
#               (delegated ratification, 00_07 BIZ.22). The question posed to the founder
#               was "which of the two surviving classes becomes the declared exemption";
#               the measurement dissolved it, because the two classes are not two
#               candidates for one tier — they are the gate's TWO TERM SETS, with
#               different exemption economics, and the code already scanned them
#               separately. So the flip is per TERM SET, not per scope:
#                 · OFFERING had exactly FOUR hits, all of them the one ratified ⛔ class
#                   (the fee rendered from a record, plus its seed). Cost of HARD = one
#                   site-keyed allowlist; benefit = `investor`/`refund`/`dividend`/`APY`
#                   can no longer enter app/ silently. Taken.
#                 · HOMONYM_CODE stays ADVISORY **by verdict, not by backlog** — see below.
#               ⛔ PRICE, stated: a lawful roll-back to MSA Option 2 (the fallback fee)
#               now costs an allowlist entry, not just a commit. That is deliberate — the
#               entry is where the verdict gets re-read.
#   ADVISORY  — HOMONYM_CODE over the response surfaces. ⛔ This tier is NOT a backlog and
#               must not be "cleared": `yield` is a CORE DOMAIN NOUN for a platform whose
#               subject is forest growth (biomass yield, crop yield), so a HARD tier would
#               tax every honest use of it forever, while the risk it actually guards —
#               a label a CUSTOMER READS — is already HARD one tier up, in locale VALUES.
#               🔴 "FLIP A SCOPE TO HARD ONCE IT REACHES ZERO" STOOD HERE AND IS
#               UNREACHABLE AS WRITTEN — measured 2026-09-10, and the reason is two
#               RATIFIED verdicts sitting inside the scope, not unfinished work.
#               `contracts/show.rb` renders `early_exit_fee_percent` FROM THE RECORD
#               (historical contracts must show the term they were signed under, ⛔ in
#               00_07 BIZ.22), and its seed sibling is held pending a founder's word.
#               A criterion that can only be met by violating a verdict is not a
#               criterion. The honest form is ZERO UNTRIAGED hits, with each surviving
#               one belonging to a NAMED class — and after the 2026-09-10 sweep the
#               remaining set is exactly two such classes, nothing loose:
#                 · ratified ⛔ sites (the fee rendered from a record, and its seed);
#                 · the `yield` class — and its triage is sharper than "homonym",
#                   sharper too than the label "biological" this line used to carry.
#                   RESPONSE KEYS among those hits are exactly TWO: `yield_impact`
#                   (ai_insight_blueprint) and `biomass_yield_kg`
#                   (maintenance_record_blueprint) — both mean the CROP, not a return.
#                   A third candidate is the controller `permit` list, i.e. a REQUEST
#                   key; counting it as a response key repeats the very overshoot this
#                   paragraph names (re-measured 2026-09-20; 00_07 BIZ.22 said TWO and
#                   was right, this header said THREE and was not).
#                   The rest are internal identifiers, a cache key and a comment that
#                   never reach a client — i.e. the regex overshoots this gate's own
#                   declared subject ("response keys"), scanning whole lines instead.
#                   ⚠️ And "biological" under-describes them: the widest sub-group is
#                   `oracle_visions_controller`'s `@scc_yield` / `calculate_expected_yield`
#                   — EXPECTED SCC EMISSION, not a harvest. It stays out of scope for the
#                   right reason (the response key is `emission_forecast`, so no client
#                   ever sees the word), NOT because it is agronomy. Do not amnesty a
#                   profit-expectation identifier by filing it under crops.
#               ⚖️ RESOLVED 2026-09-22: the ratified ⛔ sites became the declared
#               exemption (RATIFIED_CODE_SITES below, keyed to the PATH so a third file
#               carrying the same wording still fails), and the `yield` class became the
#               declared REASON this tier stays advisory. Both classes were answered, not
#               one — because they were never competing for the same tier.
#
# NAMED CEILINGS [BIZ.22] — a regex cannot read intent, so each is named, not fixed:
#   (1) HOMONYM terms are gated only inside locale values, so investment framing in
#       engineering prose stays a manual-sweep concern — the ceiling DOC-T.41 already
#       accepted for the manifest, for the same reason.
#   (2) Canon docs under docs/*.md are NOT scanned. They legitimately name the code's
#       own symbols — 05_03 documents `slash(address investor, …)` because that IS the
#       ABI. Scanning them produced ~100 downstream lines per run, which is how an advisory
#       tier becomes noise nobody reads.
#       🔴 CORRECTED 2026-08-29: this clause used to end "a securities-safe rename will carry
#       that prose with it — canon prose is downstream of the rename, not separate work",
#       which PRESUMED a rename that was in fact REFUSED. ⚖️ won't-do, ratified 2026-07-25:
#       `address investor` in `.sol`/subgraph/ABI stays — renaming it is a subgraph migration
#       across ~250 sites for zero gain (home: 00_07 BIZ.22). ⚠️ That figure is the
#       2026-07-25 verdict's ORDER-OF-MAGNITUDE estimate, not a re-measured count —
#       the inventory command is `grep -rn "address investor" contracts/ docs/`. The ceiling is therefore
#       permanent, not transitional: canon prose naming the ABI symbol is CORRECT, and a
#       future sweep must not read this exemption as an invitation to "finish the job".
#       ⛔ BUT THE EXEMPTION IS NARROWER THAN THE WORD. It covers the ABI symbol
#       `address investor`; it does NOT cover Ruby that merely shares the noun.
#       `05_01` names `verify_investor!` — a Ruby method, not the ABI parameter — and
#       that method (declared in the Polygon compliance service) plus its single
#       production caller `HadronKycVerificationWorker` are REAL remaining
#       code-layer debt, not exempt symbols.
#       Read "the ABI stays" as being about `.sol`/subgraph/ABI only; anything else
#       carrying the noun is triaged on its own merits.
#   (3) Ruby comments are skipped: internal engineering notes are not what a customer
#       receives, and they were a third of the first advisory run.
#   (4) OFFERING matches `early[\s_-]?exit[\s_-]?fee` and therefore does NOT catch
#       "Early Termination Fee" / "Early Termination Charge". This is load-bearing,
#       not an oversight: MSA Option 2 (the fallback fee, `msa_skeleton §B.6.3`) would
#       pass this gate GREEN if a lawyer ever restores it. ⛔ Sharpening the terms onto
#       fee/refund vocabulary was CONSIDERED AND REFUSED 2026-08-30 (00_07 BIZ.22),
#       on three grounds: a silent return is already covered twice NON-lexically (the
#       refund/fee code is gone, and a negative pin guards the absence of money keys in
#       the termination result); a lawful roll-back to Option 2 is deliberately kept
#       git-cheap, and a lexical gate would make exactly that noisy; and the price of
#       refusing is bounded — fee prose outside `msa_skeleton` will not red, but without
#       code and without an MSA clause such prose does not constitute Option 2.
#       ⚠️ This ceiling was declared in the tracker for weeks while this header listed
#       only three — a gate's ceilings live HERE (00_06 §3), so a fourth one known only
#       to 00_07 is a ceiling nobody reads at the moment of writing a term.
#   (5) The HARD code tier does NOT cover app/models, app/services, app/workers,
#       app/mailers, app/policies or lib — and that boundary is MEASURED, not assumed.
#       Priced 2026-09-22 before the flip (00_05 §5, «ціна периметра міряється ДО
#       вмикання»): extending OFFERING to those trees yields **14 hits**, and reading
#       them shows most are legitimate, so the extension is work first and a gate second.
#       The composition, because it is the useful half of the number:
#         · six in `blockchain_burning_service` — the ABI blob plus Ruby locals named
#           after its `address investor` parameter (`investor_address`,
#           `investor_balance_wei`). The ABI itself is ⚖️ won't-do-rename (2026-07-25);
#           its Ruby shadows are the debt ceiling (2) already names;
#         · four in `minting_rollback_service` — `refund_points`, an INTERNAL release of
#           locked points, not a promise to a customer. A homonym OFFERING cannot read;
#         · `verify_investor!` + its single production caller — the real remaining debt
#           this header names under (2);
#         · one Ukrainian log line, and the `store_accessor` that declares the very
#           column the ratified ⛔ view renders.
#       ⛔ So do not "finish the job" by widening the globs: none of these reaches a
#       customer, and a tier that reds on the ABI would be off within a week. What WOULD
#       justify revisiting: `verify_investor!` renamed away, after which the service trees
#       drop to the ABI shadows alone.
# The enum value was RENAMED `investor` → `subscriber` on 2026-08-28 (BIZ.22 verdict
# ratified: service model, ERC-3643 declined), so this gate no longer has to stay silent
# about a pending decision. It still does not scan Ruby comments or canon prose (2)-(3).
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

  HARD_DOCS = %w[docs/manifest.md README.md].freeze

  # The code layer, split by TERM SET — because the two sets have different exemption
  # economics, and that is what decided the tier (⚖️ 2026-09-22, 00_07 BIZ.22).
  #   OFFERING over CODE_OFFERING_SCOPE  — HARD. These words have no legitimate
  #     non-financial reading here, and the measured population is two RATIFIED sites
  #     and nothing loose, so the tier costs one allowlist and buys a guarantee.
  #   HOMONYM_CODE over CODE_HOMONYM_SCOPE — ADVISORY, deliberately. `yield` is a CORE
  #     DOMAIN NOUN for a forest-monitoring platform (biomass yield, crop yield); a HARD
  #     tier would tax every honest use of it forever, and the risk it guards — a label a
  #     customer READS — is already HARD one tier up, in locale VALUES.
  CODE_OFFERING_SCOPE = %w[app/controllers/api/**/*.rb app/blueprints/**/*.rb
                           app/views/**/*.rb app/views/**/*.erb db/seeds.rb].freeze
  CODE_HOMONYM_SCOPE  = %w[app/controllers/api/**/*.rb app/blueprints/**/*.rb].freeze

  # ⛔ RATIFIED EXEMPTIONS — keyed to the SITE, never to the term. A third file carrying
  # the same wording still fails, which is the whole point: the verdicts below are about
  # these two places, not about the word.
  #   · app/views/components/contracts/show.rb — renders `early_exit_fee_percent` FROM
  #     THE RECORD, because a historical contract must show the term it was signed under
  #     (⛔ 00_07 BIZ.22; the fee itself was removed from the product by ⚖️ Option 1,
  #     founder 2026-08-29, msa_skeleton §B.6.3).
  #   · db/seeds.rb — the sibling seed value, held pending a founder's word (00_07 BIZ.22).
  # A DEAD entry here is FATAL, not tidied away: an exemption that outlives its verdict is
  # how a gate goes quietly green over work nobody re-read (00_05 §4, «гейт, який ти щойно
  # збудував: на чому він упаде хибно»).
  RATIFIED_CODE_SITES = {
    "app/views/components/contracts/show.rb" => [ "early-exit fee framing" ],
    "db/seeds.rb"                            => [ "early-exit fee framing" ]
  }.freeze

  # `hit` is "path:lineno — label: text" as `scan` builds it.
  def ratified?(hit)
    path, rest = hit.split(":", 2)
    labels = RATIFIED_CODE_SITES[path] or return false
    labels.any? { |l| rest.to_s.include?(" — #{l}:") }
  end

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

  # Returns { hard: [...], advisory: [...], dead_exemptions: [...] }.
  def audit(root = ROOT)
    hard = []
    advisory = []

    files(root, "config/locales/**/*.yml").each do |rel|
      vals = numbered(root, rel).filter_map { |no, l| (v = locale_value(l)) && [ no, v ] }
      hard.concat(scan(rel, vals, OFFERING), scan(rel, vals, HOMONYM))
    end
    files(root, *HARD_DOCS).each { |rel| hard.concat(scan(rel, numbered(root, rel), OFFERING)) }

    code_offering = files(root, *CODE_OFFERING_SCOPE)
                      .flat_map { |rel| scan(rel, code_lines(root, rel), OFFERING) }
    hard.concat(code_offering.reject { |h| ratified?(h) })

    files(root, *CODE_HOMONYM_SCOPE).each { |rel| advisory.concat(scan(rel, code_lines(root, rel), HOMONYM_CODE)) }

    # ⚠️ Only for the real repository. A fixture tree never contains the ratified sites,
    # so asking this of one would report every exemption dead on every spec run — the
    # «gate that constructs the defect it then reports» shape.
    dead = root == ROOT ? dead_exemptions(code_offering) : []

    { hard:, advisory:, dead_exemptions: dead }
  end

  # An exemption that matches nothing is an exemption whose verdict has been superseded —
  # report it BY NAME so the same commit removes it. Pure over a hit-list, so it is
  # testable without a tree.
  def dead_exemptions(code_offering_hits)
    RATIFIED_CODE_SITES.flat_map do |path, labels|
      labels.reject { |l| code_offering_hits.any? { |h| h.start_with?("#{path}:") && h.include?(" — #{l}:") } }
            .map { |l| "#{path} — «#{l}»" }
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  r = OfferingLexicon.audit

  unless r[:advisory].empty?
    # Grouped, not per-line: this prints on every CI run, and 44 advisory lines every
    # time is how a report stops being read. One row per file says "still open"; the
    # lines are one --verbose away.
    by_file = r[:advisory].group_by { |a| a[/\A[^:]+/] }
    puts "offering_lexicon_check — ADVISORY: #{r[:advisory].size} homonym hit(s) in " \
         "#{by_file.size} file(s). This tier is advisory BY VERDICT, not by backlog " \
         "(⚖️ 2026-09-22, 00_07 BIZ.22): `yield` is a core domain noun here, and the " \
         "label a customer reads is guarded HARD one tier up. Read them, do not clear them:"
    by_file.sort.each do |file, hits|
      puts "  · #{file} — #{hits.size} (lines #{hits.map { |h| h[/:(\d+) —/, 1] }.join(',')})"
    end
    r[:advisory].each { |a| puts "    · #{a}" } if ARGV.include?("--verbose")
    puts
  end

  unless r[:dead_exemptions].empty?
    warn "offering_lexicon_check ✗ — a RATIFIED exemption matched nothing (00_07 BIZ.22):"
    r[:dead_exemptions].each { |d| warn "  ✗ #{d}" }
    warn "\nThe site this exemption was written for is gone, so the exemption now shields " \
         "nothing and would silently shield the NEXT thing put there. Remove the entry from " \
         "RATIFIED_CODE_SITES in the same commit that removed the site."
    exit 1
  end

  if r[:hard].empty?
    puts "offering_lexicon_check ✓ — storefront clean and code layer free of offering " \
         "lexicon outside the two ratified sites (BIZ.22)."
    exit 0
  else
    warn "offering_lexicon_check ✗ — offering lexicon returned to a customer-facing surface (BIZ.22):"
    r[:hard].each { |h| warn "  ✗ #{h}" }
    warn "\nThese surfaces are what the acquirer receives. Use service wording " \
         "(contracted / service fee / emission / cluster health) — canon 00_04 §1. " \
         "A ratified ⛔ site is exempted BY PATH in RATIFIED_CODE_SITES, never by term."
    exit 1
  end
end
