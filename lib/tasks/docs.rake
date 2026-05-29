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
# Pure file I/O, no Rails boot needed.
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

    failed = []
    failed << "dangling doc links" unless dangling.empty?
    failed << "✅ Статус docs without a TRL" unless trl_missing.empty?
    abort("docs:check_refs FAILED — #{failed.join(', ')}") unless failed.empty?
  end
end
