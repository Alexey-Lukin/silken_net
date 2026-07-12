# frozen_string_literal: true

# [00_07 DRY tooling] `rake tracker:check` — lints docs/00_07_Action_Plan_Tracker.md:
#   - duplicate task IDs across the WHOLE file — every #### heading AND every table-row
#     first-cell, in EVERY section incl. 📌 Backlog / 🗄️ Архів (caught the HW.20
#     BME280↔Buffer-Cap collision; the registry table-row span closed the
#     DOC-T.12 #### ↔ table-row blind spot; widened to global to catch the
#     `OPS.5` §07-heading ↔ 📌-backlog-row collision)
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
    # caught (the OPS.5 collision). Same `all_item_ids` span as the inbound-ref guard.
    dups     = Tracker::Dashboard.duplicate_ids(md)
    issues   = Tracker::Dashboard.issues(items)
    dangling = Tracker::Dashboard.dangling_refs(items)
    sect     = Tracker::Dashboard.section_dangling_refs(items)
    filesect = Tracker::Dashboard.file_section_dangling_refs(md)
    home     = Tracker::Dashboard.section_home_violations(items)
    inbound  = Tracker::Dashboard.inbound_ref_violations
    prose    = Tracker::Dashboard.inbound_prose_ref_violations
    chem     = Tracker::Dashboard.chem_note_ref_violations
    chemdups = Tracker::Dashboard.chem_note_ids(md).tally.select { |_, c| c > 1 }
    chemambig = Tracker::Dashboard.chem_ambiguous_token_lines(md)
    runon    = Tracker::Dashboard.inline_residual_runon(md)
    verdict  = Tracker::Dashboard.verdict_lead_violations(md)
    metaform = Tracker::Dashboard.meta_form_violations(md)
    cluster  = Tracker::Dashboard.cluster_marker_violations(md)

    puts "00_07 lint — #{items.size} #### items (#{Tracker::Dashboard.open_items(items).size} actionable)"
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
    if inbound.empty?
      puts "  inbound refs:     every `00_07 — ID` ref resolves to a real item ✓"
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
    abort("tracker:check FAILED") if dups.any? || issues.any? || dangling.any? || sect.any? || filesect.any? || home.any? || inbound.any? || prose.any? || chem.any? || chemdups.any? || chemambig.any? || runon.any? || verdict.any? || metaform.any? || cluster.any?
  end
end
