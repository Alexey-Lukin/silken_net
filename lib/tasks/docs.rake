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
    rtc_phantom = []  # hard: phantom RTC register DR>19 (chip has only DR0..DR19)
    lorenz_drift = [] # hard: Lorenz β formula re-stated outside 03_04 owner
    gp_clamp     = [] # hard: retired growth_points clamp `(…,10,63)` (pre-FW.29-PACK)
    deprecated  = []  # hard: retired SSOT term reappeared (DocsLinter::DEPRECATED_TERMS)
    label_drift = []  # hard: link label leads with a different NN_NN than its href resolves to
    magic_drift = []  # soft: magic-marker hex ≠ BE/LE ASCII of its quoted name
    bare_refs   = []  # hard: bare code-span `NN_NN §X` ref that should be a full link
    rate_drift  = []  # hard: tokenomics/carbon rate value re-stated outside its One-Home (05_03/07_01)
    solc_drift  = []  # hard: solc/pragma version re-stated outside 05_03 owner (code SSOT = foundry.toml)
    ai_vendor   = []  # hard: AI-vendor name (Gemini/Cursor/…) re-stated outside 00_02 §2 roster (use roles)
    bare_doc    = []  # hard: bare code-span `NN_NN` doc-id (no §) that should be a full link
    xref_form   = []  # hard: doc-id link label not in the single code-span form (00_06 §1)
    sec_after_link = [] # hard: bare §X dangling after a whole-doc link — fold into label (DOC-T.16)
    superseded_fm = [] # hard: superseded term (ATECC608B) in 🎯/Статус front-matter
    src_line_refs = [] # hard: volatile `*.c`/`*.h`/`*.rb` source line-refs (DOC-T.15)
    graph_docs  = {}  # id "NN_NN" → text, for the #anchor-resolution gate (DocsGraph)
    doc_trls    = {}  # basename → member-TRL int (from ✅ Статус), for the 00_03 §1 band guard

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
        if (mt = section[/Поточний TRL[^\n]*?TRL\s*(\d)/, 1] || section[/Conceptual\s*\(TRL\s*(\d)/, 1] || section[/TRL\s*(\d)/, 1])
          doc_trls[base] = mt.to_i
        end
      end

      # [RTC reg-map drift] register availability is SSOT-owned by 03_01 §2; any
      # other doc asserting "DRn free/reserve" drifts (caught the stale
      # "DR15 наразі резерв" in 03_02/00_07/03_03 after FW.2 claimed DR15).
      rtc_drift.concat(DocsLinter.rtc_register_allocation_drift(base, text).map { |h| "#{base}: #{h}" })
      # [RTC phantom register] STM32WLE5JC has only DR0..DR19; any DRn with n>19 is
      # non-existent hardware (caught phantom DR20-DR31 Edge-RL + DR20-DR21 ring + DR24-DR26).
      rtc_phantom.concat(DocsLinter.rtc_register_out_of_range(text).map { |h| "#{base}: #{h}" })
      lorenz_drift.concat(DocsLinter.lorenz_formula_drift(base, text).map { |h| "#{base}: #{h}" })
      gp_clamp.concat(DocsLinter.growth_points_clamp_drift(base, text).map { |h| "#{base}: #{h}" })
      deprecated.concat(DocsLinter.deprecated_terms(base, text).map { |h| "#{base}: #{h}" })
      label_drift.concat(DocsLinter.link_label_target_mismatch(text).map { |h| "#{base}: #{h}" })
      magic_drift.concat(DocsLinter.magic_marker_hex_drift(text).map { |h| "#{base}: #{h}" })
      bare_refs.concat(DocsLinter.bare_section_ref(base, text).map { |h| "#{base}: #{h}" })
      rate_drift.concat(DocsLinter.tokenomics_rate_drift(base, text).map { |h| "#{base}: #{h}" })
      solc_drift.concat(DocsLinter.solc_pragma_version_drift(base, text).map { |h| "#{base}: #{h}" })
      ai_vendor.concat(DocsLinter.ai_vendor_name_drift(base, text).map { |h| "#{base}: #{h}" })
      bare_doc.concat(DocsLinter.bare_doc_ref(base, text, valid_ids).map { |h| "#{base}: #{h}" })
      xref_form.concat(DocsLinter.crossref_label_form(text).map { |h| "#{base}: #{h}" })
      sec_after_link.concat(DocsLinter.section_ref_after_doclink(base, text).map { |h| "#{base}: #{h}" })
      superseded_fm.concat(DocsLinter.superseded_term_in_frontmatter(base, text).map { |h| "#{base}: #{h}" })
      src_line_refs.concat(DocsLinter.source_line_ref_drift(base, text))
    end

    # [external doc-path drift] HARD — non-docs repo files (.github/**, root *.md, source
    # trees) reference canon docs by path too; a renamed/renumbered doc leaves THEM stale
    # and the in-docs gates never see it (the .github + bin/app/spec blind spot that hid
    # 00_07→00_05 + 08_07→08_03 + 00_08→00_07 + 03_05-rename). Validate every
    # `docs/NN_NN_Name` resolves to a current doc.
    root_dir = File.expand_path("..", DOCS_DIR)
    # Scope: .github/** + root *.md + source trees (code comments reference canon docs by
    # path too and rot on a renumber — the bin/app/spec blind spot that hid 00_08→00_07 +
    # 03_05-rename residue). Text source extensions only (skips contracts/out JSON +
    # binaries). Exempt the linter + its spec: they cite stale paths as deliberate examples.
    ext_exempt = %w[lib/docs_linter.rb spec/lib/docs_linter_spec.rb].freeze
    source_glob = File.join(root_dir, "{bin,lib,app,firmware,contracts,spec,scripts,tools}",
                            "**", "*.{rb,sh,c,h,sol,py,rake,erb}")
    external_files = (Dir[File.join(root_dir, ".github", "**", "*")].select { |p| File.file?(p) } +
                      Dir[File.join(root_dir, "*.md")] +
                      Dir[source_glob].select { |p| File.file?(p) })
                     .reject { |f| ext_exempt.include?(f.delete_prefix("#{root_dir}/")) }
    ext_drift = external_files.flat_map do |f|
      rel = f.delete_prefix("#{root_dir}/")
      DocsLinter.external_doc_path_drift(rel, File.read(f), existing)
    rescue ArgumentError
      [] # skip non-UTF-8 / binary files
    end

    # [DOC-T.15] volatile source line-refs in .github/** too (docs already scanned in
    # the loop above). HARD since 2026-06-10 — the stale-blocker carriers (05_02
    # §Блокери BLOCKER-01 + copilot-instructions blocker table) were de-reffed.
    Dir[File.join(root_dir, ".github", "**", "*")].select { |p| File.file?(p) }.each do |f|
      rel = f.delete_prefix("#{root_dir}/")
      src_line_refs.concat(DocsLinter.source_line_ref_drift(rel, File.read(f)))
    rescue ArgumentError
      next # skip non-UTF-8 / binary files
    end

    # [DOC-T.16] the docs/protocols/ subtree references canon by relative path and
    # sits OUTSIDE the top-level `files` loop; scan it for §-after-doclink too —
    # canon refs must stay consistent wherever they live. (The broader ref-integrity
    # family needs relative-href support before it can cover protocols/ → 00_07 DOC-T.26.)
    (Dir[File.join(DOCS_DIR, "**", "*.md")] - files).each do |f|
      base = File.basename(f, ".md")
      sec_after_link.concat(DocsLinter.section_ref_after_doclink(base, File.read(f)).map { |h| "#{base}: #{h}" })
    rescue ArgumentError
      next # skip non-UTF-8 / binary files
    end

    # [TRL single-value] HARD — 00_03 §1 per-module matrix cells single 1-9.
    # [TRL range-consistency] HARD — a doc's member-TRL stays inside its module band
    # (00_03 §1): band well-formed + row ≤ max member + member ≤ target (see linter).
    matrix      = File.join(DOCS_DIR, "00_03_TRL_Matrix_HIL_and_Beyond.md")
    matrix_text = File.exist?(matrix) ? File.read(matrix) : nil
    trl_ranges  = matrix_text ? DocsLinter.trl_matrix_range_violations(matrix_text) : []
    trl_band    = matrix_text ? DocsLinter.trl_range_consistency(matrix_text, doc_trls) : []

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
    if src_line_refs.empty?
      puts "  source line-refs: no volatile `*.c`/`*.h`/`*.rb` in docs/ + .github/ (cite symbol/#define) ✓"
    else
      puts "  SOURCE LINE-REF DRIFT (#{src_line_refs.uniq.size}) — volatile `*.c`/`*.h`/`*.rb` (DOC-T.15: cite symbol/#define):"
      src_line_refs.sort.uniq.first(40).each { |s| puts "    ✗ #{s}" }
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
    if sec_after_link.empty?
      puts "  §-after-link:   no bare §X dangling after a whole-doc link (all folded) ✓"
    else
      puts "  ✗ §-after-link — fold §X into the label `[`NN_NN §X`](Doc)` (#{sec_after_link.size}) — HARD (DOC-T.16):"
      sec_after_link.sort.first(50).each { |s| puts "    · #{s}" }
    end
    if rate_drift.empty?
      puts "  rate One-Home: no tokenomics/carbon rate value restated outside 05_03/07_01 ✓"
    else
      puts "  RATE DRIFT (#{rate_drift.size}) — mint/carbon rate value belongs only in 05_03 / 07_01 §3:"
      rate_drift.sort.each { |d| puts "    ✗ #{d}" }
    end
    if solc_drift.empty?
      puts "  solc One-Home: no solc/pragma version restated outside 05_03 ✓"
    else
      puts "  SOLC VERSION DRIFT (#{solc_drift.size}) — pragma/solc version belongs only in 05_03 (code = foundry.toml):"
      solc_drift.sort.each { |d| puts "    ✗ #{d}" }
    end
    if ai_vendor.empty?
      puts "  AI-roster One-Home: no AI-vendor name restated outside 00_02 §2 (roles) ✓"
    else
      puts "  AI-VENDOR DRIFT (#{ai_vendor.size}) — vendor belongs only in 00_02 §2 roster (use frontier-LLM/coding-agent):"
      ai_vendor.sort.each { |d| puts "    ✗ #{d}" }
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
    if trl_band.empty?
      puts "  TRL band:       every doc member-TRL within its 00_03 §1 module band ✓"
    else
      puts "  TRL BAND INCONSISTENCY (#{trl_band.size}) — doc TRL vs 00_03 §1 per-module band:"
      trl_band.sort.each { |r| puts "    ✗ #{r}" }
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
    if rtc_phantom.empty?
      puts "  RTC phantom:    no DR>19 (chip has only DR0..DR19) ✓"
    else
      puts "  RTC PHANTOM REGISTER (#{rtc_phantom.size}) — STM32WLE5JC has only DR0..DR19:"
      rtc_phantom.sort.each { |d| puts "    ✗ #{d}" }
    end
    if lorenz_drift.empty?
      puts "  Lorenz formula: no β `8.0/3.0` re-stated outside owner (03_04 §4.1) ✓"
    else
      puts "  LORENZ-FORMULA DRIFT (#{lorenz_drift.size}) — σ/ρ/β values are owned by 03_04 §4.1:"
      lorenz_drift.sort.each { |d| puts "    ✗ #{d}" }
    end
    if gp_clamp.empty?
      puts "  growth_points:  no retired GP formula (`10,63` / `reward / 2` / `50 - deviation`) outside owner (03_04 §4.3) ✓"
    else
      puts "  GROWTH_POINTS FORMULA DRIFT (#{gp_clamp.size}) — [E.63] live form is `metabolic_health(delta_t)` (03_04 §4.3):"
      gp_clamp.sort.each { |d| puts "    ✗ #{d}" }
    end
    if deprecated.empty?
      puts "  deprecated terms: no retired SSOT tokens present ✓"
    else
      puts "  DEPRECATED TERMS (#{deprecated.size}) — retired SSOT tokens (DocsLinter::DEPRECATED_TERMS):"
      deprecated.sort.each { |d| puts "    ✗ #{d}" }
    end
    if superseded_fm.empty?
      puts "  superseded front-matter: no reversed-decision term in any 🎯/Статус ✓"
    else
      puts "  SUPERSEDED TERM IN FRONT-MATTER (#{superseded_fm.size}) — 🎯/Статус must name the CURRENT decision:"
      superseded_fm.sort.each { |d| puts "    ✗ #{d}" }
    end
    if label_drift.empty?
      puts "  link label↔href: every doc-link label leads with the doc it points to ✓"
    else
      puts "  LINK LABEL↔HREF MISMATCH (#{label_drift.size}) — label cites a different doc than its href:"
      label_drift.sort.each { |d| puts "    ✗ #{d}" }
    end
    if xref_form.empty?
      puts "  xref form:      every doc-id link label leads with code-span `NN_NN` (one form) ✓"
    else
      puts "  XREF FORM (#{xref_form.size}) — doc-id link label not in code-span form (run scripts/normalize_crossrefs.rb):"
      xref_form.sort.first(40).each { |d| puts "    ✗ #{d}" }
    end
    if ext_drift.empty?
      puts "  external refs:  every docs/NN_NN path in .github/ + root *.md + source trees resolves ✓"
    else
      puts "  EXTERNAL DOC-PATH DRIFT (#{ext_drift.size}) — stale docs/NN_NN ref outside docs/ (.github / root md / source):"
      ext_drift.sort.each { |d| puts "    ✗ #{d}" }
    end

    failed = []
    failed << "dangling doc links" unless dangling.empty?
    failed << "✅ Статус docs without a TRL" unless trl_missing.empty?
    failed << "TRL ranges in 00_03 §1 matrix" unless trl_ranges.empty?
    failed << "TRL band inconsistency (doc TRL vs 00_03 §1 module band)" unless trl_band.empty?
    failed << "ToC drift (run docs:toc)" unless toc_drift.empty?
    failed << "canon docs hosting blocker sections (→ 00_07)" unless blocker_sections.empty?
    failed << "docs missing the standard skeleton" unless conformance.empty?
    failed << "RTC register-map drift (availability claimed outside 03_01)" unless rtc_drift.empty?
    failed << "phantom RTC register DR>19 (STM32WLE5JC has only DR0..DR19)" unless rtc_phantom.empty?
    failed << "Lorenz-formula drift (β re-stated outside 03_04 §4.1)" unless lorenz_drift.empty?
    failed << "retired growth_points clamp `(…,10,63)` (FW.29-PACK → 03_04 §4.3)" unless gp_clamp.empty?
    failed << "deprecated SSOT terms present" unless deprecated.empty?
    failed << "superseded term in front-matter (🎯/Статус names a reversed decision)" unless superseded_fm.empty?
    failed << "tokenomics/carbon rate restated outside One-Home (05_03/07_01)" unless rate_drift.empty?
    failed << "solc/pragma version restated outside One-Home (05_03; code = foundry.toml)" unless solc_drift.empty?
    failed << "AI-vendor name restated outside One-Home (00_02 §2 roster; use roles)" unless ai_vendor.empty?
    failed << "bare code-span `NN_NN §X` refs (should be `[`…`](Doc)` links)" unless bare_refs.empty?
    failed << "bare code-span `NN_NN` doc-ids (should be `[`…`](Doc)` links)" unless bare_doc.empty?
    failed << "link label↔href mismatches" unless label_drift.empty?
    failed << "doc-id link labels not in code-span form (00_06 §1)" unless xref_form.empty?
    failed << "§-after-link refs (DOC-T.16 — fold §X into the link label)" unless sec_after_link.empty?
    failed << "dangling #anchors (fragment ≠ heading slug)" unless dangling_anchors.empty?
    failed << "stale external docs/NN_NN refs (.github / root *.md / source)" unless ext_drift.empty?
    failed << "volatile source line-refs `*.c`/`*.h`/`*.rb` (DOC-T.15 — cite symbol/#define)" unless src_line_refs.empty?
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
