# frozen_string_literal: true

# [00_07 DRY tooling] `rake tracker:check` — lints docs/00_07_Action_Plan_Tracker.md:
#   - duplicate task IDs across BOTH #### headings AND registry table-row IDs
#     (caught the HW.20 BME280↔Buffer-Cap collision 2026-05-29; the table-row span
#     closes the DOC.12 #### ↔ table-row blind spot 2026-06-01)
#   - #3 conformance: every open #### item has a priority + a → canon-ref meta-line
#   - §-section resolution: a `NN_NN §X` canon-ref's §X must be a real heading in the
#     target (caught 12 stale §BLOCKER-N / wrong-doc-id refs orphaned by blockers→00_07)
#   - section↔canon-home: a #### under `## §NN` must canon-ref module NN (canon-mirror;
#     killed the §06-deploy-under-§04 "DevOps" drift, 2026-06-01)
# Engine: lib/tracker/dashboard.rb (pure Ruby; the 🚦 Dashboard stays human-curated,
# so drift/regenerate are intentionally not wired — this is a guard, not an overwriter).
require_relative "../tracker/dashboard"

namespace :tracker do
  desc "Lint 00_07: duplicate IDs + #3 conformance (priority + canon-ref per item)"
  task :check do
    md       = File.read(Tracker::Dashboard::DEFAULT_PATH)
    items    = Tracker::Dashboard.parse(md)
    # dup tally spans BOTH #### heading IDs and registry table-row IDs, so an ID
    # split across a table row + a #### heading (the DOC.12 collision) is caught.
    dups     = (items.map(&:id) + Tracker::Dashboard.table_row_ids(md)).tally.select { |_, v| v > 1 }
    issues   = Tracker::Dashboard.issues(items)
    dangling = Tracker::Dashboard.dangling_refs(items)
    sect     = Tracker::Dashboard.section_dangling_refs(items)
    home     = Tracker::Dashboard.section_home_violations(items)

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
    if home.empty?
      puts "  section-home:     every #### under §NN canon-refs module NN ✓"
    else
      puts "  section↔home mismatches (#{home.size}) — item canon-ref ≠ its §NN section module:"
      home.each { |h| puts "    - #{h}" }
    end
    abort("tracker:check FAILED") if dups.any? || issues.any? || dangling.any? || sect.any? || home.any?
  end
end
