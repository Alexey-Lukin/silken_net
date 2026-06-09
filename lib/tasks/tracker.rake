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
# Engine: lib/tracker/dashboard.rb (pure Ruby; the 🚦 Dashboard stays human-curated,
# so drift/regenerate are intentionally not wired — this is a guard, not an overwriter).
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

    puts "00_07 lint — #{items.size} #### items (#{Tracker::Dashboard.open_items(items).size} actionable)"
    puts "  duplicate IDs:    #{dups.empty? ? 'none ✓' : dups.inspect}"
    if issues.empty?
      puts "  #3 conformance:   every item has priority + executor + canon-ref ✓"
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
    abort("tracker:check FAILED") if dups.any? || issues.any? || dangling.any? || sect.any? || filesect.any? || home.any? || inbound.any? || prose.any? || chem.any? || chemdups.any? || chemambig.any?
  end
end
