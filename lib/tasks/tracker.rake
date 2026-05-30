# frozen_string_literal: true

# [09_06 DRY tooling] `rake tracker:check` — lints docs/09_06_Action_Plan_Tracker.md:
#   - duplicate task IDs (caught the HW.20 BME280↔Buffer-Cap collision, 2026-05-29)
#   - #3 conformance: every open #### item has a priority + a → canon-ref meta-line
# Engine: lib/tracker/dashboard.rb (pure Ruby; the 🚦 Dashboard stays human-curated,
# so drift/regenerate are intentionally not wired — this is a guard, not an overwriter).
require_relative "../tracker/dashboard"

namespace :tracker do
  desc "Lint 09_06: duplicate IDs + #3 conformance (priority + canon-ref per item)"
  task :check do
    items    = Tracker::Dashboard.parse(File.read(Tracker::Dashboard::DEFAULT_PATH))
    dups     = items.map(&:id).tally.select { |_, v| v > 1 }
    issues   = Tracker::Dashboard.issues(items)
    dangling = Tracker::Dashboard.dangling_refs(items)

    puts "09_06 lint — #{items.size} #### items (#{Tracker::Dashboard.open_items(items).size} actionable)"
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
    abort("tracker:check FAILED") if dups.any? || issues.any? || dangling.any?
  end
end
