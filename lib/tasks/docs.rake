# frozen_string_literal: true

# [SSOT anti-drift] `rake docs:check_refs` — lints cross-references in docs/*.md:
#   HARD  (gates CI): every markdown link to a local doc `](NN_NN_Name)` resolves
#                     to an existing docs/NN_NN_Name.md (catches renamed/typo'd docs).
#   SOFT  (advisory): every inline `NN_NN §Ref` whose §Ref names a section must
#                     have a matching heading in the target doc (catches the
#                     "label cites a section that isn't there" drift, e.g. the
#                     06_02 §Workload-Identity / 07_04 §SLA refs found 2026-05-29).
#   HARD  (gates CI): every doc with a `## ✅ Статус` section declares a TRL there
#                     (Поточний TRL / Conceptual (TRL …)) — catches the 06_04-class
#                     "Статус without a readiness level" gap. All 50 docs pass today.
#   HARD  (gates CI): the 00_06 §1 per-module TRL matrix has single-value cells
#                     (1-9), never a range — 00_07 §1.1 Current TRL is single-select.
#   ADVISORY (→ HARD post-sweep): no canon doc hosts a "🛑 Блокери" / "✅ Архів
#                     вирішених блокерів" section — ALL blockers (open + closed) live
#                     in 00_08 (decided 2026-05-29); canon keeps design substance as body prose.
# Pure file I/O, no Rails boot needed. Engines: lib/docs_linter.rb + lib/docs_toc.rb (unit-tested).
require_relative "../docs_linter"
require_relative "../docs_toc"

namespace :docs do
  DOCS_DIR = File.expand_path("../../docs", __dir__)
  DOC_RE   = /\A\d\d_\d\d_/

  desc "Lint docs/*.md cross-references (doc-existence hard, §-section advisory)"
  task :check_refs do
    files = Dir[File.join(DOCS_DIR, "*.md")]
    existing = files.map { |f| File.basename(f, ".md") }.to_set
    headings = files.to_h do |f|
      [ File.basename(f, ".md"), File.readlines(f).grep(/^\#{1,6}\s/).join("\n").downcase ]
    end

    dangling    = []  # hard: link target doc missing
    suspect     = []  # soft: §-section label not found in target headings
    trl_missing = []  # hard: ## ✅ Статус section without a TRL declaration

    files.each do |f|
      base = File.basename(f, ".md")
      text = File.read(f)

      # Markdown links to local NN_NN docs: [label](NN_NN_Name) | (NN_NN_Name#anchor)
      text.scan(/\[([^\]]*)\]\((\d\d_\d\d_[A-Za-z0-9_]+)(?:#[^)]*)?\)/) do |label, target|
        dangling << "#{base} → `#{target}` (doc not found)" unless existing.include?(target)

        # If the visible label cites `§Ref`, verify Ref appears in a target heading.
        next unless existing.include?(target)
        ref = label[/§\s*([0-9A-Za-zА-Яа-яІіЇїЄє.\-]+)/, 1]
        next unless ref && ref.length >= 2

        unless headings[target].include?(ref.downcase)
          suspect << "#{base}: label `§#{ref}` → #{target} (no heading contains '#{ref}')"
        end
      end

      # [TRL presence] a doc with a ✅ Статус section must declare its TRL there.
      lines = text.lines
      si = lines.index { |l| l =~ /^\#{1,3}\s.*Статус/ }
      if si
        rest = lines[(si + 1)..] || []
        ei = rest.index { |l| l =~ /^\#{2}\s/ }
        section = (ei ? rest[0...ei] : rest).join
        trl_missing << base unless section =~ /Поточний TRL|TRL\s*\d|Conceptual\s*\(TRL/
      end
    end

    # [TRL single-value] HARD — 00_06 §1 per-module matrix cells single 1-9.
    matrix     = File.join(DOCS_DIR, "00_06_Strategic_Roadmap_and_HIL_Simulators.md")
    trl_ranges = File.exist?(matrix) ? DocsLinter.trl_matrix_range_violations(File.read(matrix)) : []

    # [Blockers → 00_08] ADVISORY (→ HARD once the sweep removes them all). Canon
    # docs must not host a 🛑/✅-archive blocker section; 00_08 is the tracker — exempt.
    blocker_sections = files.reject { |f| File.basename(f).start_with?("00_08") }
                            .flat_map { |f| DocsLinter.canon_blocker_sections(File.read(f)).map { |h| "#{File.basename(f, '.md')}: #{h}" } }

    # [ToC sync] HARD — docs with TOC:AUTO markers must match current headings
    # (regen is a no-op when in sync). Run `bin/rails docs:toc` to fix drift.
    toc_drift = files.select { |f| DocsToc.markers?(File.read(f)) }
                     .select { |f| DocsToc.regen(File.read(f)).last }
                     .map { |f| File.basename(f, ".md") }

    puts "docs:check_refs — #{files.size} docs scanned"
    if dangling.empty?
      puts "  doc links:      all resolve ✓"
    else
      puts "  DANGLING doc links (#{dangling.size}):"
      dangling.sort.uniq.each { |d| puts "    ✗ #{d}" }
    end
    unless suspect.empty?
      puts "  ⚠️ §-section labels with no matching heading (#{suspect.uniq.size}) — advisory:"
      suspect.sort.uniq.first(40).each { |s| puts "    · #{s}" }
    end
    if trl_missing.empty?
      puts "  TRL presence:   every ✅ Статус doc declares a TRL ✓"
    else
      puts "  MISSING TRL in ✅ Статус (#{trl_missing.size}):"
      trl_missing.sort.uniq.each { |d| puts "    ✗ #{d}" }
    end
    if trl_ranges.empty?
      puts "  TRL single-value: 00_06 §1 matrix cells all single 1-9 ✓"
    else
      puts "  TRL RANGE in 00_06 §1 matrix (#{trl_ranges.size}):"
      trl_ranges.each { |r| puts "    ✗ #{r}" }
    end
    if blocker_sections.empty?
      puts "  blockers→00_08:  no canon doc hosts a 🛑/✅-archive blocker section ✓"
    else
      puts "  ⚠️ canon docs still hosting blocker sections (#{blocker_sections.size}) — advisory, migrate to 00_08:"
      blocker_sections.sort.each { |b| puts "    · #{b}" }
    end
    if toc_drift.empty?
      puts "  ToC sync:       every TOC:AUTO doc matches its headings ✓"
    else
      puts "  ToC DRIFT (#{toc_drift.size}) — run `bin/rails docs:toc`:"
      toc_drift.each { |d| puts "    ✗ #{d}" }
    end

    failed = []
    failed << "dangling doc links" unless dangling.empty?
    failed << "✅ Статус docs without a TRL" unless trl_missing.empty?
    failed << "TRL ranges in 00_06 §1 matrix" unless trl_ranges.empty?
    failed << "ToC drift (run docs:toc)" unless toc_drift.empty?
    abort("docs:check_refs FAILED — #{failed.join(', ')}") unless failed.empty?
  end

  desc "Regenerate the 📑 Зміст ToC between TOC:AUTO markers in docs that have them"
  task :toc do
    files = Dir[File.join(DOCS_DIR, "*.md")]
    regenerated = files.select do |f|
      md = File.read(f)
      next false unless DocsToc.markers?(md)

      new_md, changed = DocsToc.regen(md)
      File.write(f, new_md) if changed
      changed
    end.map { |f| File.basename(f, ".md") }
    puts "docs:toc — regenerated #{regenerated.size} doc(s)#{": #{regenerated.join(', ')}" unless regenerated.empty?}"
  end
end
