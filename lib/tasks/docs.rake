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
#   HARD  (gates CI): no canon doc hosts a blocker section (🛑/✅ + Блокери/Архів) —
#                     ALL blockers live in 00_08 (sweep complete 2026-05-30); open ones
#                     are reframed in-doc to non-blocker headings + a → 00_08 pointer.
#   HARD  (gates CI): every canon NN_NN doc carries the standard skeleton — ✅ Статус
#                     + top 🔗 Cross-references + auto-ToC (00_07 §8). Exempt: 00_00
#                     (index), 00_08 (tracker / blocker home), *_appendix_*.
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
    rtc_drift   = []  # hard: RTC register availability claimed outside 03_01 owner
    deprecated  = []  # hard: retired SSOT term reappeared (DocsLinter::DEPRECATED_TERMS)

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

      # [RTC reg-map drift] register availability is SSOT-owned by 03_01 §2; any
      # other doc asserting "DRn free/reserve" drifts (caught the stale
      # "DR15 наразі резерв" in 03_02/00_08/03_03 after FW.2 claimed DR15).
      rtc_drift.concat(DocsLinter.rtc_register_allocation_drift(base, text).map { |h| "#{base}: #{h}" })
      deprecated.concat(DocsLinter.deprecated_terms(text).map { |h| "#{base}: #{h}" })
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

    # [Standard conformance] HARD — every canon NN_NN doc carries the standard
    # skeleton (✅ Статус + top 🔗 Cross-references + auto-ToC). Sweep done 2026-05-30.
    conformance = files.flat_map do |f|
      v = DocsLinter.conformance_violations(File.basename(f, ".md"), File.read(f))
      v.empty? ? [] : [ "#{File.basename(f, '.md')}: missing #{v.join(', ')}" ]
    end

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
    if conformance.empty?
      puts "  conformance:    every canon doc carries Статус + Cross-references + ToC ✓"
    else
      puts "  STANDARD non-conformance (#{conformance.size}):"
      conformance.sort.each { |c| puts "    ✗ #{c}" }
    end
    if rtc_drift.empty?
      puts "  RTC reg-map:    no out-of-owner DRn availability claims ✓"
    else
      puts "  RTC-MAP DRIFT (#{rtc_drift.size}) — register availability is owned by 03_01 §2:"
      rtc_drift.sort.each { |d| puts "    ✗ #{d}" }
    end
    if deprecated.empty?
      puts "  deprecated terms: no retired SSOT tokens present ✓"
    else
      puts "  DEPRECATED TERMS (#{deprecated.size}) — retired SSOT tokens (DocsLinter::DEPRECATED_TERMS):"
      deprecated.sort.each { |d| puts "    ✗ #{d}" }
    end

    failed = []
    failed << "dangling doc links" unless dangling.empty?
    failed << "✅ Статус docs without a TRL" unless trl_missing.empty?
    failed << "TRL ranges in 00_06 §1 matrix" unless trl_ranges.empty?
    failed << "ToC drift (run docs:toc)" unless toc_drift.empty?
    failed << "canon docs hosting blocker sections (→ 00_08)" unless blocker_sections.empty?
    failed << "docs missing the standard skeleton" unless conformance.empty?
    failed << "RTC register-map drift (availability claimed outside 03_01)" unless rtc_drift.empty?
    failed << "deprecated SSOT terms present" unless deprecated.empty?
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
