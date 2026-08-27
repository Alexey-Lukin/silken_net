# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [00_07 DRY tooling] `rake tracker:check` — lints docs/00_07_Action_Plan_Tracker.md:
#   - duplicate task IDs across the WHOLE file — every #### heading AND every table-row
#     first-cell, in EVERY section incl. 📌 Backlog / 🗄️ Архів (caught the HW.20
#     BME280↔Buffer-Cap collision; the registry table-row span closed the
#     DOC-T.12 #### ↔ table-row blind spot; widened to global to catch the
#     a §07-heading ↔ 📌-backlog-row ID collision)
#   - #3 conformance: every open #### item has a priority + a → canon-ref meta-line
#   - §-section resolution: a `NN_NN §X` canon-ref's §X must be a real heading in the
#     target (caught 12 stale §BLOCKER-N / wrong-doc-id refs orphaned by blockers→00_07)
#   - section↔canon-home: a #### under `## §NN` must canon-ref module NN (canon-mirror;
#     killed the §06-deploy-under-§04 "DevOps" drift)
# Engine: lib/tracker/dashboard.rb (pure Ruby; pure guard — the 🚦 do-now view is a
# hand-curated Critical Path in the doc (DOC-T.16), so there is no render/overwrite path).
require_relative "../tracker/dashboard"

namespace :tracker do
  desc "Lint 00_07: duplicate IDs + #3 conformance (priority + canon-ref per item)"
  task :check do
    md       = File.read(Tracker::Dashboard::DEFAULT_PATH)
    items    = Tracker::Dashboard.parse(md)
    # dup tally spans the WHOLE file (all #### headings + all table-row first-cells,
    # incl. 📌 Backlog / 🗄️ Архів) → a backlog/archive row reusing an active ID is
    # caught (a heading-vs-backlog-row collision). Same `all_item_ids` span as the inbound-ref guard.
    dups     = Tracker::Dashboard.duplicate_ids(md)
    issues   = Tracker::Dashboard.issues(items)
    dangling = Tracker::Dashboard.dangling_refs(items)
    sect     = Tracker::Dashboard.section_dangling_refs(items)
    filesect = Tracker::Dashboard.file_section_dangling_refs(md)
    home     = Tracker::Dashboard.section_home_violations(items)
    orphan   = Tracker::Dashboard.orphan_item_violations(md)
    inbound  = Tracker::Dashboard.inbound_ref_violations
    inbndpop = Tracker::Dashboard.inbound_ref_population
    prose    = Tracker::Dashboard.inbound_prose_ref_violations
    chem     = Tracker::Dashboard.chem_note_ref_violations
    chemdups = Tracker::Dashboard.chem_note_ids(md).tally.select { |_, c| c > 1 }
    chemambig = Tracker::Dashboard.chem_ambiguous_token_lines(md)
    runon    = Tracker::Dashboard.inline_residual_runon(md)
    verdict  = Tracker::Dashboard.verdict_lead_violations(md)
    labour   = Tracker::Dashboard.labour_split_lead(md)
    metaform = Tracker::Dashboard.meta_form_violations(md)
    cluster  = Tracker::Dashboard.cluster_marker_violations(md)
    bench    = Tracker::Dashboard.bench_tag_violations(md)
    stalewho = Tracker::Dashboard.stale_who(md)
    thinwho  = Tracker::Dashboard.understated_who(md)
    leadform = Tracker::Dashboard.residual_lead_form_violations(md)
    leadpop  = Tracker::Dashboard.residual_lead_population(md)
    prio     = Tracker::Dashboard.priority_order_violations(md)
    priosect = Tracker::Dashboard.priority_ordered_sections(md)

    puts "00_07 lint — #{items.size} #### items (#{Tracker::Dashboard.open_items(md)} з відкритими residual'ами)"
    puts "  duplicate IDs:    #{dups.empty? ? 'none ✓' : dups.inspect}"
    if issues.empty?
      puts "  #3 conformance:   every item has priority + executor + stage + canon-ref ✓"
    else
      puts "  #3 conformance gaps (#{issues.size}):"
      issues.each { |i| puts "    - #{i}" }
    end
    if dangling.empty?
      puts "  canon refs:       all resolve to docs/NN_NN_*.md ✓"
    else
      puts "  dangling canon refs (#{dangling.size}):"
      dangling.each { |d| puts "    - #{d}" }
    end
    if sect.empty?
      puts "  canon §-sections: every `NN_NN §X` ref resolves to a heading ✓"
    else
      puts "  stale canon §-refs (#{sect.size}) — § X absent in target (renamed/removed section):"
      sect.each { |s| puts "    - #{s}" }
    end
    if filesect.empty?
      puts "  00_07 §-refs:     every NN_NN §X ref (incl. backlog/archive cells) resolves ✓"
    else
      puts "  unresolved 00_07 §-refs (#{filesect.size}) — §X absent in target (collapsed/renamed section):"
      filesect.each { |s| puts "    - #{s}" }
    end
    if home.empty?
      puts "  section-home:     every #### under §NN canon-refs module NN ✓"
    else
      puts "  section↔home mismatches (#{home.size}) — item canon-ref ≠ its §NN section module:"
      home.each { |h| puts "    - #{h}" }
    end
    # [DOC-T.49] pre-section orphan — HARD: an item outside every registry section is
    # invisible to the parser, so all gates above it check blind and stay green. (00_06 §3.)
    if orphan.empty?
      puts "  item visibility:  every #### item sits inside a registry section (parser sees all) ✓"
    else
      puts "  ORPHANED items (#{orphan.size}) — outside any registry section, INVISIBLE to every gate above:"
      orphan.each { |o| puts "    - #{o}" }
    end
    if inbound.empty?
      puts "  inbound refs:     every 00_07 item-ref resolves ✓ (#{inbndpop} refs, both dialects)"
    else
      puts "  dangling inbound 00_07 item-refs (#{inbound.size}) — ref to a non-existent tracker ID:"
      inbound.each { |i| puts "    - #{i}" }
    end
    if prose.empty?
      puts "  prose ID-refs:    every `→ 00_07 (ID, …)` prose ref resolves to a real item ✓"
    else
      puts "  dangling prose 00_07 ID-refs (#{prose.size}) — ID cited after a 00_07 link is not a real item:"
      prose.each { |p| puts "    - #{p}" }
    end
    if chem.empty? && chemdups.empty? && chemambig.empty?
      puts "  CHEM.N notes:     every CHEM.N ref resolves to a defined in-silico note ✓"
    else
      puts "  dangling CHEM.N refs (#{chem.size}) / dup defs (#{chemdups.size}) / ambiguous tokens (#{chemambig.size}) — in-silico note ref/ID drift:"
      chem.each { |c| puts "    - #{c}" }
      chemdups.each { |id, n| puts "    - #{id} defined #{n}× in 00_07" }
      chemambig.each { |a| puts "    - #{a}" }
    end
    # [founder 2026-06-14] inline residual run-on — HARD (joins the abort below). The
    # DOC-T.19 sweep took 00_07 to 0 inline run-on (all residuals vertical); the guard now
    # holds the line. (00_06 §3 recipe.)
    if runon.empty?
      puts "  residual lists:   no inline run-on (≥2 `· [ ]` per line) — vertical ✓"
    else
      puts "  inline run-on residual lists (#{runon.size}) — vertical-list standard violated (00_07 intro):"
      runon.each { |r| puts "    - #{r}" }
    end
    # [DOC-T.19, founder 2026-06-14] verdict-lead — EVERY item body leads with `- **Стан:**`
    # (Universal-Стан, max homogeneity). HARD (joins abort below): the DOC-T.19 sweep took
    # 00_07 to 0 non-Стан leads across §00–§08 (all 138 items), the guard now holds the line.
    # (00_06 §3 recipe.)
    if verdict.empty?
      puts "  verdict-lead:     every item body leads with `- **Стан:**` ✓"
    else
      puts "  verdict-lead non-Стан leads (#{verdict.size}) — Universal-Стан standard violated (00_07 intro): #{verdict.first(8).join(', ')}…"
    end
    # [DOC-T.63, founder ban 2026-07-05] labour-split lead — the Стан-lead opens with the
    # SUBSTANCE, never with «Machine-half ✅» / «Машинна половина ЗАКРИТА» / «вичерпано»
    # (WHO + STAGE already carry the division of labour). HARD from birth: the 8 live cases
    # were swept in the same commit that added this gate, so it starts at 0 and holds the
    # line the written ban could not — it came back three times in three days after the ban,
    # then five more in Ukrainian. (00_06 §3 recipe.)
    if labour.empty?
      puts "  labour-split lead: no Стан-lead opens with the division of labour ✓"
    else
      puts "  labour-split leads (#{labour.size}) — lead with the verdict/root, not «machine-half» (deep_archival.md, founder 2026-07-05):"
      labour.each { |r| puts "    - #{r}" }
    end
    # [DOC-T.23, founder 2026-06-14] meta-line form — WHO ∈ {🤖,👤,🤖+👤} + no tail after
    # canon-ref. HARD (joins abort): the DOC-T.23 sweep took 00_07 to 0 violations. (00_06 §3.)
    if metaform.empty?
      puts "  meta-line form:   every meta `**P?** · WHO · STAGE · ref` (WHO canonical, no tail) ✓"
    else
      puts "  meta-line form violations (#{metaform.size}) — non-canonical WHO / trailing tail (00_07 intro):"
      metaform.each { |m| puts "    - #{m}" }
    end
    # [DOC-T.34 ③] дім-кластер markers — HARD: symmetric form `[кластер:slug:дім|важіль]`,
    # exactly one дім + ≥1 важіль per slug (half-migrated clusters are the drift). (00_06 §3.)
    if cluster.empty?
      puts "  кластер markers:  every [кластер:slug:…] symmetric (1 дім + ≥1 важіль) ✓"
    else
      puts "  кластер-marker violations (#{cluster.size}) — malformed/asymmetric (00_07 §розмітка):"
      cluster.each { |c| puts "    - #{c}" }
    end
    # [DOC-T.34 ①] bench-session tag symmetry — HARD: RUNBOOK §6 session registry ⇆
    # 00_07 `[bench:slug]` tags, both directions. (00_06 §3.)
    if bench.empty?
      puts "  bench sessions:   [bench:slug] tags ⇆ RUNBOOK §6 registry symmetric ✓"
    else
      puts "  bench-tag violations (#{bench.size}) — tag↔registry asymmetry (RUNBOOK §6):"
      bench.each { |b| puts "    - #{b}" }
    end
    # [DOC-T.52 · widened DOC-T.55] stale WHO — HARD: meta-line WHO must stay the UNION of
    # OPEN residuals, so a shipped half drops its glyph. `meta_form_violations` only checks
    # the token's SHAPE, never whether it still matches the checkboxes — that blind spot let
    # 3 items advertise free 🤖 work that no longer existed, making a "what's doable" scan
    # lie. DOC-T.55 closed the two holes the first cut left: it read ONE glyph of a
    # three-member enum (a meta ⚖️ nobody awaits — the costliest executor to summon —
    # passed forever), and it exited on the EMPTY SET, so a finished item kept a full WHO
    # axis with nothing open. Coverage is asymmetric: ⚖️ ⊂ 👤, so a meta 👤 is backed by an
    # open 👤 OR ⚖️, never the reverse. Exempts 🔗-led (delegated elsewhere) and WHO-less
    # (🌿-led) residuals — item-wide, since an undetermined executor backs any glyph; and
    # exempts 🌿/⚫ items with nothing open, where WHO names a FUTURE executor. (00_06 §3.)
    if stalewho.empty?
      puts "  stale WHO:        every meta glyph backed by an open residual carrying it ✓"
    else
      puts "  stale WHO (#{stalewho.size}) — meta-line claims an executor no open residual backs:"
      stalewho.each { |s| puts "    - #{s}" }
    end
    # [DOC-T.54] understated WHO — HARD: the REVERSE axis of DOC-T.52. That guard catches
    # meta OVERSTATING; nothing caught meta UNDERSTATING — an open residual whose executor
    # the meta-line never declares. This direction costs more: the meta-line IS the scan
    # layer, so a pure-👤 meta over a body of 🤖 residuals reads as "nothing machine-doable
    # here" (HW.1, a P0 critical-path item, hid six). Exempts 🔗-led + glyph-less residuals
    # like its sibling — and needs NO three-executor exemption, since ⚖️ ⊂ 👤 collapses
    # {🤖,👤,⚖️} onto the legal pair 🤖+👤. Executors are read from the residual's LEADING
    # token: a 👤 line citing 🤖 work in prose is closed work, not an open claim. (00_06 §3.)
    if thinwho.empty?
      puts "  understated WHO:  every open residual's executor declared on its meta-line ✓"
    else
      puts "  understated WHO (#{thinwho.size}) — meta-line omits an executor its open residuals carry:"
      thinwho.each { |s| puts "    - #{s}" }
    end
    # [DOC-T.92] residual lead-form — HARD from birth: the intro closes the LEAD vocabulary
    # of an open residual exactly as WHO_CANON closes the meta-line, and the meta axis has
    # been gated since DOC-T.23 while the residual axis had nothing. Form-drift here
    # DISARMS a neighbour — one glyph-less leg lifts `stale_who` off the WHOLE item, and
    # both WHO gates read the executor from the LEADING token only, so a decorative lead
    # hides machine work from the scan layer. Baseline 5 (HW.33 + HW.5.IS ×4) was swept in
    # the SAME commit, so the gate never shipped over known drift. The POPULATION is printed
    # on purpose: it is the lantern — «0 violations» means «clean» only while the walk still
    # has a subject (§Guard-craft #61). (00_06 §3.)
    if leadform.empty?
      puts "  residual lead:    every open residual leads with a declared WHO / 🔗 / 🌿 ✓ (#{leadpop} residuals scanned)"
    else
      puts "  residual lead-form (#{leadform.size}) — лід ноги поза словником інтро (00_07 §розмітка):"
      leadform.each { |s| puts "    - #{s}" }
    end
    # [DOC-T.73] priority monotonicity — HARD from birth (baseline 8 violations across 5
    # sections was sorted to 0 by `scripts/tracker_sort.rb` in the SAME commit, so the
    # gate never shipped over known drift). The section COUNT is printed on purpose: it is
    # the lantern — «0 violations» means «clean» only while the scan still has a subject.
    if prio.empty?
      puts "  priority order:   P non-decreasing within each §-section ✓ (#{priosect.size} sections scanned)"
    else
      puts "  priority order (#{prio.size}) — вищий P стоїть НИЖЧЕ за нижчий:"
      prio.each { |s| puts "    - #{s}" }
    end

    abort("tracker:check FAILED") if dups.any? || issues.any? || dangling.any? || sect.any? || filesect.any? || home.any? || orphan.any? || inbound.any? || prose.any? || chem.any? || chemdups.any? || chemambig.any? || runon.any? || verdict.any? || labour.any? || metaform.any? || cluster.any? || bench.any? || stalewho.any? || thinwho.any? || leadform.any? || prio.any?
  end
end
