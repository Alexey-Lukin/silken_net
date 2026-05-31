# frozen_string_literal: true

# [SSOT anti-drift] `rake docs:check_refs` — lints cross-references in docs/*.md:
#   HARD  (gates CI): every markdown link to a local doc `](NN_NN_Name)` resolves
#                     to an existing docs/NN_NN_Name.md (catches renamed/typo'd docs).
#   SOFT  (advisory): every inline `NN_NN §Ref` whose §Ref names a section must
#                     have a matching heading in the target doc (catches the
#                     "label cites a section that isn't there" drift, e.g. the
#                     06_02 §Workload-Identity / 07_05 §SLA refs found 2026-05-29).
#   HARD  (gates CI): every doc with a `## ✅ Статус` section declares a TRL there
#                     (Поточний TRL / Conceptual (TRL …)) — catches the 06_04-class
#                     "Статус without a readiness level" gap. All 50 docs pass today.
#   HARD  (gates CI): the 00_03 §1 per-module TRL matrix has single-value cells
#                     (1-9), never a range — 00_05 §1.1 Current TRL is single-select.
#   HARD  (gates CI): no canon doc hosts a blocker section (🛑/✅ + Блокери/Архів) —
#                     ALL blockers live in 00_07 (sweep complete 2026-05-30); open ones
#                     are reframed in-doc to non-blocker headings + a → 00_07 pointer.
#   HARD  (gates CI): every canon NN_NN doc carries the standard skeleton — ✅ Статус
#                     + top 🔗 Cross-references + auto-ToC (00_06). Exempt: 00_00
#                     (index), 00_07 (tracker / blocker home), *_appendix_*.
#   HARD  (gates CI): every `#anchor` fragment in a doc-link (intra-doc `](#frag)`
#                     and cross-doc `](NN_NN_Name#frag)`) resolves to a real heading
#                     slug in the target — a stale anchor silently drops the reader
#                     at page-top and the §-label guard never sees it. Graduated
#                     from the on-demand docs:graph audit (00_06 §3) once all anchors
#                     were clean. The graph keeps the orphan/dead-end/degree lens.
# Pure file I/O, no Rails boot needed. Engines: lib/docs_linter.rb + lib/docs_toc.rb
# + lib/docs_graph.rb (anchor resolution) — all unit-tested.
require_relative "../docs_linter"
require_relative "../docs_toc"
require_relative "../docs_graph"

namespace :docs do
  DOCS_DIR = File.expand_path("../../docs", __dir__)
  DOC_RE   = /\A\d\d_\d\d_/

  desc "Lint docs/*.md cross-references (doc-existence hard, §-section advisory)"
  task :check_refs do
    files = Dir[File.join(DOCS_DIR, "*.md")]
    existing = files.map { |f| File.basename(f, ".md") }.to_set
    valid_ids = existing.filter_map { |b| b[/\A\d\d_\d\d/] }.to_set  # NN_NN of every current doc
    headings = files.to_h do |f|
      [ File.basename(f, ".md"), File.readlines(f).grep(/^\#{1,6}\s/).join("\n").downcase ]
    end

    dangling    = []  # hard: link target doc missing
    suspect     = []  # soft: §-section label not found in target headings
    trl_missing = []  # hard: ## ✅ Статус section without a TRL declaration
    rtc_drift   = []  # hard: RTC register availability claimed outside 03_01 owner
    lorenz_drift = [] # hard: Lorenz β formula re-stated outside 03_04 owner
    deprecated  = []  # hard: retired SSOT term reappeared (DocsLinter::DEPRECATED_TERMS)
    label_drift = []  # hard: link label leads with a different NN_NN than its href resolves to
    magic_drift = []  # soft: magic-marker hex ≠ BE/LE ASCII of its quoted name
    bare_refs   = []  # hard: bare code-span `NN_NN §X` ref that should be a full link
    rate_drift  = []  # hard: tokenomics/carbon rate value re-stated outside its One-Home (05_03/07_01)
    bare_doc    = []  # hard: bare code-span `NN_NN` doc-id (no §) that should be a full link
    graph_docs  = {}  # id "NN_NN" → text, for the #anchor-resolution gate (DocsGraph)

    files.each do |f|
      base = File.basename(f, ".md")
      text = File.read(f)
      if (gid = base[/\A\d\d_\d\d/])
        graph_docs[gid] = text
      end

      # [dangling] every markdown link to a local NN_NN doc must resolve to a file.
      text.scan(/\[([^\]]*)\]\((\d\d_\d\d_[A-Za-z0-9_]+)(?:#[^)]*)?\)/) do |_label, target|
        dangling << "#{base} → `#{target}` (doc not found)" unless existing.include?(target)
      end

      # [§-label drift] advisory — a label's `§Ref` must name a real heading in the
      # target (tested pure fn; canonical ref format → 00_06 §1, kept strict).
      suspect.concat(DocsLinter.section_label_drift(text, headings).map { |h| "#{base}: #{h}" })

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
      # "DR15 наразі резерв" in 03_02/00_07/03_03 after FW.2 claimed DR15).
      rtc_drift.concat(DocsLinter.rtc_register_allocation_drift(base, text).map { |h| "#{base}: #{h}" })
      lorenz_drift.concat(DocsLinter.lorenz_formula_drift(base, text).map { |h| "#{base}: #{h}" })
      deprecated.concat(DocsLinter.deprecated_terms(text).map { |h| "#{base}: #{h}" })
      label_drift.concat(DocsLinter.link_label_target_mismatch(text).map { |h| "#{base}: #{h}" })
      magic_drift.concat(DocsLinter.magic_marker_hex_drift(text).map { |h| "#{base}: #{h}" })
      bare_refs.concat(DocsLinter.bare_section_ref(base, text).map { |h| "#{base}: #{h}" })
      rate_drift.concat(DocsLinter.tokenomics_rate_drift(base, text).map { |h| "#{base}: #{h}" })
      bare_doc.concat(DocsLinter.bare_doc_ref(base, text, valid_ids).map { |h| "#{base}: #{h}" })
    end

    # [TRL single-value] HARD — 00_03 §1 per-module matrix cells single 1-9.
    matrix     = File.join(DOCS_DIR, "00_03_TRL_Matrix_HIL_and_Beyond.md")
    trl_ranges = File.exist?(matrix) ? DocsLinter.trl_matrix_range_violations(File.read(matrix)) : []

    # [Blockers → 00_07] ADVISORY (→ HARD once the sweep removes them all). Canon
    # docs must not host a 🛑/✅-archive blocker section; 00_07 is the tracker — exempt.
    blocker_sections = files.reject { |f| File.basename(f).start_with?("00_07") }
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

    # [#anchor resolution] HARD — every link #fragment resolves to a heading slug
    # in its target (DocsGraph engine, mirrors docs:graph). Cross-doc links to an
    # absent target are left to the dangling guard above.
    anchor_sets      = graph_docs.transform_values { |t| DocsGraph.anchor_set(t) }
    dangling_anchors = DocsGraph.dangling_anchors(graph_docs, anchor_sets)

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
    unless magic_drift.empty?
      puts "  ⚠️ magic-marker hex ≠ BE/LE ASCII of its name (#{magic_drift.uniq.size}) — advisory:"
      magic_drift.sort.uniq.first(40).each { |s| puts "    · #{s}" }
    end
    if bare_refs.empty?
      puts "  bare §-refs:    no bare code-span `NN_NN §X` outside owner docs (all linked) ✓"
    else
      by_doc = bare_refs.group_by { |s| s[/\A\d\d_\d\d/] }.transform_values(&:size).sort_by { |d, n| [ -n, d ] }
      puts "  ✗ bare code-span `NN_NN §X` refs — must be `[`…`](Doc)` links (#{bare_refs.size}) — HARD:"
      puts "      per-doc: " + by_doc.map { |d, n| "#{d}:#{n}" }.join("  ")
      bare_refs.sort.first(50).each { |s| puts "    · #{s}" }
    end
    if bare_doc.empty?
      puts "  bare doc-ids:   no bare code-span `NN_NN` doc-id outside owner docs (all linked) ✓"
    else
      by_doc = bare_doc.group_by { |s| s[/\A\d\d_\d\d/] }.transform_values(&:size).sort_by { |d, n| [ -n, d ] }
      puts "  ✗ bare code-span `NN_NN` doc-ids — must be `[`…`](Doc)` links (#{bare_doc.size}) — HARD:"
      puts "      per-doc: " + by_doc.map { |d, n| "#{d}:#{n}" }.join("  ")
      bare_doc.sort.first(50).each { |s| puts "    · #{s}" }
    end
    if rate_drift.empty?
      puts "  rate One-Home: no tokenomics/carbon rate value restated outside 05_03/07_01 ✓"
    else
      puts "  RATE DRIFT (#{rate_drift.size}) — mint/carbon rate value belongs only in 05_03 / 07_01 §3:"
      rate_drift.sort.each { |d| puts "    ✗ #{d}" }
    end
    if trl_missing.empty?
      puts "  TRL presence:   every ✅ Статус doc declares a TRL ✓"
    else
      puts "  MISSING TRL in ✅ Статус (#{trl_missing.size}):"
      trl_missing.sort.uniq.each { |d| puts "    ✗ #{d}" }
    end
    if trl_ranges.empty?
      puts "  TRL single-value: 00_03 §1 matrix cells all single 1-9 ✓"
    else
      puts "  TRL RANGE in 00_03 §1 matrix (#{trl_ranges.size}):"
      trl_ranges.each { |r| puts "    ✗ #{r}" }
    end
    if blocker_sections.empty?
      puts "  blockers→00_07:  no canon doc hosts a 🛑/✅-archive blocker section ✓"
    else
      puts "  ⚠️ canon docs still hosting blocker sections (#{blocker_sections.size}) — advisory, migrate to 00_07:"
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
    if dangling_anchors.empty?
      puts "  #anchors:       every doc-link #fragment resolves to a heading slug ✓"
    else
      puts "  DANGLING #anchors (#{dangling_anchors.size}) — fragment has no matching heading slug:"
      dangling_anchors.each { |h| puts "    ✗ #{h[:from]} → #{h[:to]}##{h[:anchor]}" }
    end
    if rtc_drift.empty?
      puts "  RTC reg-map:    no out-of-owner DRn availability claims ✓"
    else
      puts "  RTC-MAP DRIFT (#{rtc_drift.size}) — register availability is owned by 03_01 §2:"
      rtc_drift.sort.each { |d| puts "    ✗ #{d}" }
    end
    if lorenz_drift.empty?
      puts "  Lorenz formula: no β `8.0/3.0` re-stated outside owner (03_04 §4.1) ✓"
    else
      puts "  LORENZ-FORMULA DRIFT (#{lorenz_drift.size}) — σ/ρ/β values are owned by 03_04 §4.1:"
      lorenz_drift.sort.each { |d| puts "    ✗ #{d}" }
    end
    if deprecated.empty?
      puts "  deprecated terms: no retired SSOT tokens present ✓"
    else
      puts "  DEPRECATED TERMS (#{deprecated.size}) — retired SSOT tokens (DocsLinter::DEPRECATED_TERMS):"
      deprecated.sort.each { |d| puts "    ✗ #{d}" }
    end
    if label_drift.empty?
      puts "  link label↔href: every doc-link label leads with the doc it points to ✓"
    else
      puts "  LINK LABEL↔HREF MISMATCH (#{label_drift.size}) — label cites a different doc than its href:"
      label_drift.sort.each { |d| puts "    ✗ #{d}" }
    end

    failed = []
    failed << "dangling doc links" unless dangling.empty?
    failed << "✅ Статус docs without a TRL" unless trl_missing.empty?
    failed << "TRL ranges in 00_03 §1 matrix" unless trl_ranges.empty?
    failed << "ToC drift (run docs:toc)" unless toc_drift.empty?
    failed << "canon docs hosting blocker sections (→ 00_07)" unless blocker_sections.empty?
    failed << "docs missing the standard skeleton" unless conformance.empty?
    failed << "RTC register-map drift (availability claimed outside 03_01)" unless rtc_drift.empty?
    failed << "Lorenz-formula drift (β re-stated outside 03_04 §4.1)" unless lorenz_drift.empty?
    failed << "deprecated SSOT terms present" unless deprecated.empty?
    failed << "tokenomics/carbon rate restated outside One-Home (05_03/07_01)" unless rate_drift.empty?
    failed << "bare code-span `NN_NN §X` refs (should be `[`…`](Doc)` links)" unless bare_refs.empty?
    failed << "bare code-span `NN_NN` doc-ids (should be `[`…`](Doc)` links)" unless bare_doc.empty?
    failed << "link label↔href mismatches" unless label_drift.empty?
    failed << "dangling #anchors (fragment ≠ heading slug)" unless dangling_anchors.empty?
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
