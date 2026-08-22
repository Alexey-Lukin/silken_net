# SPDX-License-Identifier: AGPL-3.0-or-later
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
#                     (1-9), never a range — 00_03 §1 fixes the NASA 1-9 scale.
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
#   HARD  (gates CI): every numbered `NN_NN §X` ref in a canon doc resolves to a real
#                     heading-anchor in the target (boundary-aware, bare+linked, comma-
#                     joined — Tracker::Dashboard.file_section_dangling_refs, the same
#                     resolver tracker:check runs on 00_07). Closed the canon blind spot
#                     where cross-doc §-refs had only the substring `section_label_drift`
#                     advisory (let 08_02 §1.x / 05_03 §749 / 02_03 §4.А rot). Exempt
#                     00_06 (cites stale refs as drift examples) + 00_07 (tracker:check).
# Pure file I/O, no Rails boot needed. Engines: lib/docs_linter.rb + lib/docs_toc.rb
# + lib/docs_graph.rb (anchor resolution) + lib/tracker/dashboard.rb (canon §-resolution)
# — all unit-tested.
require "yaml"
require_relative "../docs_linter"
require_relative "../docs_toc"
require_relative "../docs_graph"
require_relative "../tracker/dashboard"

namespace :docs do
  DOCS_DIR = File.expand_path("../../docs", __dir__)
  DOC_RE   = /\A\d\d_\d\d_/

  # [DOC-T.70, ⚖️ ratified 2026-08-09] Pages whose SUBJECT is not a technology.
  # TRL (NASA/ISO 16290) measures the readiness of a TECHNOLOGY, and 00_03 §1 says so
  # in as many words: organisational, process and security maturity do NOT sit on that
  # scale — «TRL партнерств» / «TRL процесу» is a CATEGORY ERROR, not a low score. Yet
  # the presence-check below demanded a TRL from every doc carrying a ✅ Статус block,
  # so such a page could not honestly say "not applicable" without losing its Статус:
  # the norm forbade exactly what the gate compelled. Hence a DECLARED exception —
  # a machine cannot tell a process page from a technology one, and inferring it would
  # be wrong in the silent direction (same reasoning as MANIFEST_TRL_OWNERS).
  # The list is a two-way pin: a page here must ALSO carry no TRL, otherwise the
  # exception would quietly become a licence to keep the category error.
  TRL_NOT_APPLICABLE = {
    "00_01" => "візія / місія / дорожня карта — намір, не готовність технології",
    "00_06" => "стандарт самих доків — процес",
    "00_05" => "AI-native операційна модель — практика роботи, не технологія",
    "00_04" => "юр/бізнес-шар NaaS — договірна, не технологічна зрілість",
    # ⚠️ ДРУГИЙ виняток усередині бандованого модуля (після 04_06), і критерій тут той
    # самий, узагальнений: предмет не є технологією, а модуль-контейнер байдужий.
    # Вартісна економіка заліза ⊥ готовність заліза: BOM-як-специфікація несе TRL і
    # живе в 02_01/02_05, BOM-як-грошовий-підсумок TRL не має. Не давати цій сторінці
    # й owner-імунітету на курс — вузький імунітет кращий за широкий.
    "02_06" => "вартісна економіка заліза — гроші, не готовність технології",
    "00_02" => "академічні партнери та IP — рівно той «TRL партнерств», що §1 називає помилкою",
    # 🔴 ФОРМА ПРАВИЛА ЗВУЖЕНА 2026-08-22, і це варте рядка: чотири записи вище лежать у
    # модулях БЕЗ band-рядка (00 і 07), тож критерій де-факто читався як «модуль не
    # технологічний». 04_06 — перший виняток УСЕРЕДИНІ банованого модуля, тобто критерій
    # тепер той, що написаний у самому словнику: «предмет не є технологією». Механізм
    # байдужий (ключ = номер доку), і обидві перевірки band-у для цієї сторінки вироджені:
    # усі пʼять членів модуля 04 на TRL 8, ціль 9.
    "04_06" => "методологія тестування й карта покриття — практика, не технологія"
  }.freeze

  desc "Lint docs/*.md cross-references (doc-existence hard, §-section advisory)"
  task :check_refs do
    files = Dir[File.join(DOCS_DIR, "*.md")]
    existing = files.map { |f| File.basename(f, ".md") }.to_set
    valid_ids = existing.filter_map { |b| b[/\A\d\d_\d\d/] }.to_set  # NN_NN of every current doc
    headings = files.to_h do |f|
      [ File.basename(f, ".md"), File.readlines(f).grep(/^\#{1,6}\s/).join("\n").downcase ]
    end

    dangling    = []  # hard: link target doc missing
    # hard since DOC-T.48 (2026-07-25) — the name and this comment said "soft" for two
    # weeks after the flip, while line ~628 pushes it into `failed`. A gate's own comment
    # about its own severity is the one claim nothing checks (§Guard-craft #4).
    suspect     = []  # hard: §-section label not found in target headings
    trl_missing = []  # hard: ## ✅ Статус section without a TRL declaration
    trl_misapplied = [] # hard: a declared non-technology page that states a TRL anyway
    # hard: an exemption whose SUBJECT is gone. A page can be dissolved or renumbered
    # (DOC-T.68 does exactly that to 00_02/00_05/00_08), and a stale entry here would
    # silently hand its immunity to whatever document lands on that number next —
    # the freed-number face of §Guard-craft #50. An exemption must guard itself.
    trl_exempt_dead = TRL_NOT_APPLICABLE.keys.reject { |k| existing.any? { |b| b.start_with?(k) } }
    # Same class, wider surface: every doc NUMBER named in an owner/exempt constant of
    # the linter must still resolve. A freed number otherwise hands its immunity to the
    # next occupant — see DocsLinter.number_keyed_exemptions for why this is its own guard.
    exempt_dead = DocsLinter.number_keyed_exemptions.reject { |num, _| valid_ids.include?(num) }
    rtc_drift   = []  # hard: RTC register availability claimed outside 03_01 owner
    rtc_phantom = []  # hard: phantom RTC register DR>19 (chip has only DR0..DR19)
    lorenz_drift = [] # hard: Lorenz β formula re-stated outside 03_04 owner
    tl_chain_hash = [] # hard: telemetry_logs has no chain_hash column (Merkle leaf = 05_02 §E.60)
    bio_potential = [] # hard: rejected vocabulary — bio_potential is the measurand, not a routing metric (ARCH.11)
    gp_clamp     = [] # hard: retired growth_points clamp `(…,10,63)` (pre-FW.29-PACK)
    statusbyte_drift = [] # hard: retired pre-FW.29 StatusByte bit-layout (6-bit `<<6`/`0x3F`/bits 7..6) — DOC-T.43
    deprecated  = []  # hard: retired SSOT term reappeared (DocsLinter::DEPRECATED_TERMS)
    mem_links   = []  # hard: [[wiki-link]] into memory/, which lives OUTSIDE the repo
    label_drift = []  # hard: link label leads with a different NN_NN than its href resolves to
    magic_drift = []  # hard: magic-marker hex ≠ BE/LE ASCII of its quoted name (DOC-T.46 flip — deterministic byte-packing, 0 residual)
    bare_refs   = []  # hard: bare code-span `NN_NN §X` ref that should be a full link
    rate_drift  = []  # hard: tokenomics/carbon rate value re-stated outside its One-Home (05_03/00_04)
    rate_anchor = []  # hard: a rate HOME no longer matches the guard's own regex (re-price w/o updating the tripwire — DOC-T.40)
    # 🔴 Оголошені доми курсу, ЗУСТРІНУТІ у скані. Без цього гейт вироджувався
    # мовчки: резолв іде за префіксом імені файлу, тож звільнений номер дому просто
    # ніколи не консультується, і вердикт друкував «both … ✓», вимірявши ОДИН із двох.
    # Мутаційно доведено 2026-08-22. Той самий лік, що в TRL-ліхтаря: недосяжне
    # джерело = RED зі словом «did NOT run», ніколи тихий зелений.
    rate_anchor_seen = []
    solc_drift  = []  # hard: solc/pragma version re-stated outside 05_03 owner (code SSOT = foundry.toml)
    ai_vendor   = []  # hard: AI-vendor name (Gemini/Cursor/…) re-stated outside 00_06 §5 roster (use roles)
    bare_doc    = []  # hard: bare code-span `NN_NN` doc-id (no §) that should be a full link
    xref_form   = []  # hard: doc-id link label not in the single code-span form (00_06 §1)
    sec_after_link = [] # hard: bare §X dangling after a whole-doc link — fold into label (DOC-T.16)
    superseded_fm = [] # hard: superseded term (ATECC608B) in 🎯/Статус front-matter
    src_line_refs = [] # hard: volatile `*.c`/`*.h`/`*.rb` source line-refs (DOC-T.15)
    cited_specs  = [] # hard: canon names its honesty-gates by path (DOC-T.84 друге плече)
    spec_exists  = ->(p) { File.file?(File.join(File.expand_path("..", DOCS_DIR), p)) }
    anchor_dim   = []  # hard: superseded anchor dimension range near part keyword (01_01 §1 freeze)
    thermal_drift = [] # hard: superseded HW.3.IS thermal-stress/press-fit number (01_01 §4.2 / report)
    fence_unbalanced = [] # hard: unclosed ``` code fence (odd count) desyncs fence-aware guards + truncates ToC — DOC-T.45
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

      # [TRL presence] a doc with a ✅ Статус section must declare its TRL there —
      # UNLESS its subject is not a technology at all (TRL_NOT_APPLICABLE below).
      lines = text.lines
      si = lines.index { |l| l =~ /^\#{1,3}\s.*Статус/ }
      if si && !TRL_NOT_APPLICABLE.key?(base[0, 5])
        rest = lines[(si + 1)..] || []
        ei = rest.index { |l| l =~ /^\#{2}\s/ }
        section = (ei ? rest[0...ei] : rest).join
        trl_missing << base unless section =~ /Поточний TRL|TRL\s*\d|Conceptual\s*\(TRL/
        if (mt = section[/Поточний TRL[^\n]*?TRL\s*(\d)/, 1] || section[/Conceptual\s*\(TRL\s*(\d)/, 1] || section[/TRL\s*(\d)/, 1])
          doc_trls[base] = mt.to_i
        end
      elsif si
        # Reverse half of the two-way pin: a page declared non-technology must ALSO be
        # free of a TRL claim, or the exemption silently becomes a licence to keep the
        # very category error it was granted for.
        rest = lines[(si + 1)..] || []
        ei = rest.index { |l| l =~ /^\#{2}\s/ }
        section = (ei ? rest[0...ei] : rest).join
        # Anchored on the DECLARATION form, never on the digit. ⚠️ The page that bought this
        # (its subject was literally «Beyond TRL 9») has since been dissolved by DOC-T.68
        # фаза 4, so the ground is no longer readable in the tree — ⛔ do NOT «simplify»
        # this back to a bare `TRL\s*\d`: any future page whose SUBJECT is a TRL level
        # would fire on its own topic. What makes a number a CLAIM here is the
        # skeleton's bold label, not the digit.
        trl_misapplied << "#{base} — #{TRL_NOT_APPLICABLE[base[0, 5]]}" if section =~ /\*\*Поточний TRL|\*\*TRL[[:space:]-]*\d/
      end

      # [RTC reg-map drift] register availability is SSOT-owned by 03_01 §2; any
      # other doc asserting "DRn free/reserve" drifts (caught the stale
      # "DR15 наразі резерв" in 03_02/00_07/03_03 after FW.2 claimed DR15).
      rtc_drift.concat(DocsLinter.rtc_register_allocation_drift(base, text).map { |h| "#{base}: #{h}" })
      # [RTC phantom register] STM32WLE5JC has only DR0..DR19; any DRn with n>19 is
      # non-existent hardware (caught phantom DR20-DR31 Edge-RL + DR20-DR21 ring + DR24-DR26).
      rtc_phantom.concat(DocsLinter.rtc_register_out_of_range(text).map { |h| "#{base}: #{h}" })
      lorenz_drift.concat(DocsLinter.lorenz_formula_drift(base, text).map { |h| "#{base}: #{h}" })
      tl_chain_hash.concat(DocsLinter.telemetry_log_chain_hash_drift(text).map { |h| "#{base}: #{h}" })
      bio_potential.concat(DocsLinter.bio_potential_as_metric(text).map { |h| "#{base}: #{h}" })
      gp_clamp.concat(DocsLinter.growth_points_clamp_drift(base, text).map { |h| "#{base}: #{h}" })
      statusbyte_drift.concat(DocsLinter.status_byte_layout_drift(base, text).map { |h| "#{base}: #{h}" })
      deprecated.concat(DocsLinter.deprecated_terms(base, text).map { |h| "#{base}: #{h}" })
      mem_links.concat(DocsLinter.memory_wikilink_violations(text).map { |h| "#{base}: #{h}" })
      label_drift.concat(DocsLinter.link_label_target_mismatch(text).map { |h| "#{base}: #{h}" })
      magic_drift.concat(DocsLinter.magic_marker_hex_drift(text).map { |h| "#{base}: #{h}" })
      bare_refs.concat(DocsLinter.bare_section_ref(base, text).map { |h| "#{base}: #{h}" })
      rate_drift.concat(DocsLinter.tokenomics_rate_drift(base, text).map { |h| "#{base}: #{h}" })
      rate_anchor_seen << base[/\A\d\d_\d\d/] if DocsLinter::RATE_ANCHOR_HOMES.key?(base[/\A\d\d_\d\d/])
      rate_anchor.concat(DocsLinter.tokenomics_rate_anchor(base, text))
      solc_drift.concat(DocsLinter.solc_pragma_version_drift(base, text).map { |h| "#{base}: #{h}" })
      ai_vendor.concat(DocsLinter.ai_vendor_name_drift(base, text).map { |h| "#{base}: #{h}" })
      bare_doc.concat(DocsLinter.bare_doc_ref(base, text, valid_ids).map { |h| "#{base}: #{h}" })
      xref_form.concat(DocsLinter.crossref_label_form(text).map { |h| "#{base}: #{h}" })
      sec_after_link.concat(DocsLinter.section_ref_after_doclink(base, text).map { |h| "#{base}: #{h}" })
      superseded_fm.concat(DocsLinter.superseded_term_in_frontmatter(base, text).map { |h| "#{base}: #{h}" })
      anchor_dim.concat(DocsLinter.anchor_dimension_drift(base, text).map { |h| "#{base}: #{h}" })
      thermal_drift.concat(DocsLinter.thermal_stress_drift(base, text).map { |h| "#{base}: #{h}" })
      src_line_refs.concat(DocsLinter.source_line_ref_drift(base, text))
      cited_specs.concat(DocsLinter.cited_spec_path_drift(base, text, spec_exists))
      fence_unbalanced.concat(DocsLinter.unbalanced_code_fences(text).map { |h| "#{base}: #{h}" })
    end

    # [canonical source-block pin] HARD — value-bearing const blocks that live in BOTH
    # code (the SSOT) and doc mirrors (CLAUDE.md/03_04) are pinned by SHA-256; a change in
    # the code block fails CI until the mirrors are reconciled + re-pinned (`rake docs:repin`).
    # Generalizes solc/judge-prompt drift-guard to blocks where the mirror is WANTED, not
    # forbidden. Config = lib/canonical_block_pins.yml (source-relative-to-repo-root + consts + sha).
    block_drift = []
    repo_root = File.expand_path("../..", __dir__)
    pins_path = File.join(repo_root, "lib", "canonical_block_pins.yml")
    if File.exist?(pins_path)
      (YAML.safe_load_file(pins_path) || {}).each do |key, cfg|
        src = File.join(repo_root, cfg["source"].to_s)
        unless File.exist?(src)
          block_drift << "#{key}: source #{cfg['source']} not found"
          next
        end
        block_drift.concat(
          DocsLinter.canonical_block_drift(key, File.basename(src), File.read(src), Array(cfg["consts"]), cfg["sha256"].to_s)
        )
      end
    end

    # [canon §-ref resolution] HARD — every NUMBERED `NN_NN §X` ref in a canon doc must
    # resolve to a real heading-anchor in the target (boundary-aware, bare+linked, comma/
    # list-joined — Tracker::Dashboard.file_section_dangling_refs). That resolver was
    # 00_07-only (tracker:check) + protocols-only; the canon docs cross-reference each
    # other's §-sections by the dozen and got only the weaker substring `section_label_drift`
    # ADVISORY — the blind spot that let 08_02 §1.x, 05_03 §749 (a LINE number!), 02_03 §4.А
    # rot. Exempt: 00_06 (the standard doc cites stale refs as drift EXAMPLES) + 00_07
    # (tracker:check owns its §-resolution, One-Home). Named (`§SLA`) refs stay with
    # section_label_drift — this resolver is digit-led only. (00_06 §3 recipe.)
    canon_section_exempt = /\A00_0[67]_/
    canon_secrefs = files.reject { |f| File.basename(f).match?(canon_section_exempt) }
                         .flat_map do |f|
      Tracker::Dashboard.file_section_dangling_refs(File.read(f)).map { |h| "#{File.basename(f, '.md')}: #{h}" }
    end

    # [external doc-path drift] HARD — non-docs repo files (.github/**, root *.md, source
    # trees) reference canon docs by path too; a renamed/renumbered doc leaves THEM stale
    # and the in-docs gates never see it (the .github + bin/app/spec blind spot that hid
    # 00_07→00_05 + 08_07→08_03 + 00_08→00_07 + 03_05-rename). Validate every
    # `docs/NN_NN_Name` resolves to a current doc.
    root_dir = File.expand_path("..", DOCS_DIR)
    # Scope: .github/** + root *.md + `.cursorrules` + .claude/**/*.md + deploy/** + source
    # trees (code
    # comments reference canon docs by
    # path too and rot on a renumber — the bin/app/spec blind spot that hid 00_08→00_07 +
    # 03_05-rename residue). Text source extensions only (skips contracts/out JSON +
    # binaries). Exempt the linter + its spec: they cite stale paths as deliberate examples.
    ext_exempt = %w[lib/docs_linter.rb spec/lib/docs_linter_spec.rb].freeze
    source_glob = File.join(root_dir, "{bin,lib,app,firmware,contracts,spec,scripts,tools,config,db}",
                            "**", "*.{rb,sh,c,h,sol,py,rake,erb}")
    external_files = (Dir[File.join(root_dir, ".github", "**", "*")].select { |p| File.file?(p) } +
                      Dir[File.join(root_dir, "*.md")] +
                      Dir[File.join(root_dir, ".cursorrules")].select { |p| File.file?(p) } +
                      Dir[File.join(root_dir, ".claude", "**", "*.md")].select { |p| File.file?(p) } +
                      Dir[File.join(root_dir, "deploy", "**", "*")].select { |p| File.file?(p) } +
                      Dir[source_glob].select { |p| File.file?(p) })
                     .reject { |f| ext_exempt.include?(f.delete_prefix("#{root_dir}/")) }
    ext_drift = external_files.flat_map do |f|
      rel = f.delete_prefix("#{root_dir}/")
      body = File.read(f)
      # Same file set, second axis: `external_doc_path_drift` asks whether the href
      # RESOLVES, and a link whose label cites one doc while the href points at
      # another resolves perfectly — so the two must run as a PAIR or the lie stays
      # invisible exactly on the surfaces no in-docs gate reads [DOC-T.68 закривна].
      label_drift.concat(DocsLinter.link_label_target_mismatch(body).map { |h| "#{rel}: #{h}" })
      cited_specs.concat(DocsLinter.cited_spec_path_drift(rel, body, spec_exists))
      DocsLinter.external_doc_path_drift(rel, body, existing)
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
      ptext = File.read(f)
      sec_after_link.concat(DocsLinter.section_ref_after_doclink(base, ptext).map { |h| "#{base}: #{h}" })
      fence_unbalanced.concat(DocsLinter.unbalanced_code_fences(ptext).map { |h| "#{base}: #{h}" })
    rescue ArgumentError
      next # skip non-UTF-8 / binary files
    end

    # [DOC-T.42 ②] value/owner-only guards over the EXTENDED text surface. The main
    # loop scans docs/*.md only, so docs/protocols/** + the shipped tools/cad/cem/*.json
    # were a blind spot for every value-guard — a live superseded `SF 3.4×` sat in
    # zone2_sleeve.json signed "§4.2 frozen" and nothing blinked (§01a-close 2026-07-16).
    # Structural/skeleton gates (ToC, TRL, xref-form, bare-ref) stay top-level-only: the
    # subtree has its own ref conventions (protocols_ref_check) and no canon skeleton.
    # json is scanned as TEXT on purpose — the prose `_note`/`notes` fields are exactly
    # where the stale physics froze, and cem_canon_sync pins only the numeric dims.
    ext_value_files = (Dir[File.join(DOCS_DIR, "**", "*.md")] - files) +
                      Dir[File.join(root_dir, "tools", "cad", "cem", "*.json")]
    ext_value_files.each do |f|
      base = File.basename(f).sub(/\.(?:md|json)\z/, "")
      text = begin
        File.read(f)
      rescue ArgumentError
        next # non-UTF-8 / binary
      end
      rtc_drift.concat(DocsLinter.rtc_register_allocation_drift(base, text).map { |h| "#{base}: #{h}" })
      rtc_phantom.concat(DocsLinter.rtc_register_out_of_range(text).map { |h| "#{base}: #{h}" })
      lorenz_drift.concat(DocsLinter.lorenz_formula_drift(base, text).map { |h| "#{base}: #{h}" })
      tl_chain_hash.concat(DocsLinter.telemetry_log_chain_hash_drift(text).map { |h| "#{base}: #{h}" })
      bio_potential.concat(DocsLinter.bio_potential_as_metric(text).map { |h| "#{base}: #{h}" })
      gp_clamp.concat(DocsLinter.growth_points_clamp_drift(base, text).map { |h| "#{base}: #{h}" })
      statusbyte_drift.concat(DocsLinter.status_byte_layout_drift(base, text).map { |h| "#{base}: #{h}" })
      deprecated.concat(DocsLinter.deprecated_terms(base, text).map { |h| "#{base}: #{h}" })
      mem_links.concat(DocsLinter.memory_wikilink_violations(text).map { |h| "#{base}: #{h}" })
      rate_drift.concat(DocsLinter.tokenomics_rate_drift(base, text).map { |h| "#{base}: #{h}" })
      solc_drift.concat(DocsLinter.solc_pragma_version_drift(base, text).map { |h| "#{base}: #{h}" })
      ai_vendor.concat(DocsLinter.ai_vendor_name_drift(base, text).map { |h| "#{base}: #{h}" })
      anchor_dim.concat(DocsLinter.anchor_dimension_drift(base, text).map { |h| "#{base}: #{h}" })
      thermal_drift.concat(DocsLinter.thermal_stress_drift(base, text).map { |h| "#{base}: #{h}" })
    end

    # [TRL single-value] HARD — 00_03 §1 per-module matrix cells single 1-9.
    # [TRL range-consistency] HARD — a doc's member-TRL stays inside its module band
    # (00_03 §1): band well-formed + row ≤ max member + member ≤ target (see linter).
    # Resolved by NUMBER, never by full filename: the number is the ratified stable
    # coordinate of this page, its title is not. A missing (or ambiguous) match used to
    # hand `nil` to all three TRL gates below, which then computed empty arrays and
    # passed forever — on the corpus's central honesty claim, with zero red. An empty
    # finding-set means "clean" only when the check actually RAN, so say so and go RED.
    matrix_files = files.select { |f| File.basename(f).start_with?("00_03_") }
    matrix_text  = matrix_files.one? ? File.read(matrix_files.first) : nil
    trl_dark     = matrix_text ? [] : [ "docs/00_03_*.md matched #{matrix_files.size} files — the 3 TRL gates below did NOT run" ]
    trl_ranges  = matrix_text ? DocsLinter.trl_matrix_range_violations(matrix_text) : []
    trl_band    = matrix_text ? DocsLinter.trl_range_consistency(matrix_text, doc_trls) : []

    # [manifest TRL parity] HARD — the PUBLIC manifesto states a TRL per layer and
    # is not a canon doc, so no `## ✅ Статус` exists for the band check to read
    # (DOC-T.66). Read directly; a missing file yields no claims, and the linter's
    # registry then reports the loss rather than passing on an empty set.
    manifest_f  = File.join(DOCS_DIR, "manifest.md")
    manifest_trl = matrix_text && File.exist?(manifest_f) ?
                     DocsLinter.manifest_trl_parity(matrix_text, File.read(manifest_f)) : []

    # [Blockers → 00_07] HARD (sweep completed 2026-05-30). Canon docs must not
    # host a 🛑/✅-archive blocker section; 00_07 is the tracker — exempt.
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
    # [DOC-T.48] HARD since 2026-07-25 (was advisory since 2026-05-30). It was the LAST
    # advisory item of the 34 `docs:check_refs` categories, sat at 0 hits across all docs,
    # and its own week-mates (bare_section_ref / bare_doc_ref, 2026-05-31) went HARD long
    # ago with no recorded reason for the exception. Precedent: DOC-T.46.
    if suspect.empty?
      puts "  §-section labels: every linked `§X` label resolves to a heading in its target ✓"
    else
      puts "  §-section labels with no matching heading (#{suspect.uniq.size}):"
      suspect.sort.uniq.first(40).each { |s| puts "    ✗ #{s}" }
    end
    if magic_drift.empty?
      puts "  magic-marker:   every 4-byte magic literal = BE/LE ASCII of its quoted name ✓"
    else
      puts "  MAGIC-MARKER HEX DRIFT (#{magic_drift.uniq.size}) — literal ≠ BE/LE packing of its quoted name (DOC-T.46):"
      magic_drift.sort.uniq.each { |s| puts "    ✗ #{s}" }
    end
    if cited_specs.empty?
      puts "  cited specs:    every `spec/…rb` named in canon + routing layer exists ✓"
    else
      puts "  CITED SPEC PATHS (#{cited_specs.uniq.size}) — canon names a guard nothing answers to (DOC-T.84):"
      cited_specs.sort.uniq.each { |x| puts "    ✗ #{x}" }
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
    if canon_secrefs.empty?
      puts "  canon §-refs:   every numbered `NN_NN §X` ref resolves to a real heading ✓"
    else
      puts "  ✗ canon §-refs — §X absent in target (collapsed/renamed/wrong section) (#{canon_secrefs.size}) — HARD:"
      canon_secrefs.sort.uniq.first(50).each { |s| puts "    · #{s}" }
    end
    if rate_drift.empty?
      puts "  rate One-Home: no tokenomics/carbon rate value restated outside 05_03/00_04 ✓"
    else
      puts "  RATE DRIFT (#{rate_drift.size}) — mint/carbon rate value belongs only in 05_03 / 00_04 §3:"
      rate_drift.sort.each { |d| puts "    ✗ #{d}" }
    end
    rate_homes_missing = DocsLinter::RATE_ANCHOR_HOMES.keys - rate_anchor_seen
    if rate_homes_missing.any?
      puts "  RATE ANCHOR DID NOT RUN (#{rate_homes_missing.size}) — declared home(s) never met in the scan:"
      rate_homes_missing.sort.each do |n|
        puts "    ✗ #{n} — RATE_ANCHOR_HOMES declares it, no doc carries that number. Freed/renamed? " \
             "The guard did NOT evaluate it; a re-price there is unguarded (DOC-T.40 / DOC-T.84)"
      end
    elsif rate_anchor.empty?
      puts "  rate anchor:    all #{DocsLinter::RATE_ANCHOR_HOMES.size} declared rate homes met and still match ✓"
    else
      puts "  RATE ANCHOR STALE (#{rate_anchor.size}) — a home was re-priced but the guard regex was not (DOC-T.40):"
      rate_anchor.sort.each { |d| puts "    ✗ #{d}" }
    end
    if solc_drift.empty?
      puts "  solc One-Home: no solc/pragma version restated outside 05_03 ✓"
    else
      puts "  SOLC VERSION DRIFT (#{solc_drift.size}) — pragma/solc version belongs only in 05_03 (code = foundry.toml):"
      solc_drift.sort.each { |d| puts "    ✗ #{d}" }
    end
    if block_drift.empty?
      puts "  canonical pins: every pinned source-block matches canonical_block_pins.yml ✓"
    else
      puts "  CANONICAL BLOCK DRIFT (#{block_drift.size}) — a pinned code block changed; reconcile mirrors + `rake docs:repin`:"
      block_drift.sort.each { |d| puts "    ✗ #{d}" }
    end
    if ai_vendor.empty?
      puts "  AI-roster One-Home: no AI-vendor name restated outside 00_06 §5 (roles) ✓"
    else
      puts "  AI-VENDOR DRIFT (#{ai_vendor.size}) — vendor belongs only in 00_06 §5 roster (use frontier-LLM/coding-agent):"
      ai_vendor.sort.each { |d| puts "    ✗ #{d}" }
    end
    if anchor_dim.empty?
      puts "  anchor dims One-Home: no superseded flange/Zone2 range outside the 01_01 §1 freeze ✓"
    else
      puts "  ANCHOR DIM DRIFT (#{anchor_dim.size}) — superseded range near part keyword; collapse to the 01_01 §1 frozen value:"
      anchor_dim.sort.each { |d| puts "    ✗ #{d}" }
    end
    if thermal_drift.empty?
      puts "  thermal-stress One-Home: no superseded HW.3.IS SF/P_c number outside 01_01 §4.2 / the report ✓"
    else
      puts "  THERMAL-STRESS DRIFT (#{thermal_drift.size}) — superseded baseline SF/P_c near a thermal keyword; use the 01_01 §4.2 frozen value:"
      thermal_drift.sort.each { |d| puts "    ✗ #{d}" }
    end
    if trl_missing.empty?
      puts "  TRL presence:   every ✅ Статус doc declares a TRL ✓"
    else
      puts "  MISSING TRL in ✅ Статус (#{trl_missing.size}):"
      trl_missing.sort.uniq.each { |d| puts "    ✗ #{d}" }
    end
    unless trl_exempt_dead.empty?
      puts "  TRL EXEMPTION WITHOUT A SUBJECT (#{trl_exempt_dead.size}) — the page is gone; decide the entry explicitly:"
      trl_exempt_dead.sort.each { |k| puts "    ✗ #{k} — #{TRL_NOT_APPLICABLE[k]}" }
    end
    if exempt_dead.empty?
      puts "  exemption subjects: every NN_NN named in an owner/exempt constant resolves ✓"
    else
      puts "  EXEMPTION WITHOUT A SUBJECT (#{exempt_dead.size}) — inherited immunity; decide each explicitly:"
      exempt_dead.sort.each { |num, consts| puts "    ✗ #{num} — granted by #{consts.join(', ')}" }
    end
    if trl_misapplied.empty?
      puts "  TRL applicability: no declared non-technology page states a TRL ✓"
    else
      puts "  TRL ON A NON-TECHNOLOGY PAGE (#{trl_misapplied.size}) — 00_03 §1 calls this a category error:"
      trl_misapplied.sort.each { |d| puts "    ✗ #{d}" }
    end
    unless trl_dark.empty?
      puts "  TRL SOURCE DARK — the matrix doc could not be resolved:"
      trl_dark.each { |d| puts "    ✗ #{d}" }
    end
    # The three ✓ lines below are suppressed while the source is dark — a green tick
    # next to "did NOT run" is the very thing this lantern exists to prevent.
    if trl_ranges.any?
      puts "  TRL RANGE in 00_03 §1 matrix (#{trl_ranges.size}):"
      trl_ranges.each { |r| puts "    ✗ #{r}" }
    elsif trl_dark.empty?
      puts "  TRL single-value: 00_03 §1 matrix cells all single 1-9 ✓"
    end
    if trl_band.any?
      puts "  TRL BAND INCONSISTENCY (#{trl_band.size}) — doc TRL vs 00_03 §1 per-module band:"
      trl_band.sort.each { |r| puts "    ✗ #{r}" }
    elsif trl_dark.empty?
      puts "  TRL band:       every doc member-TRL within its 00_03 §1 module band ✓"
    end
    if manifest_trl.any?
      puts "  MANIFEST TRL DRIFT (#{manifest_trl.size}) — PUBLIC claim vs 00_03 §1:"
      manifest_trl.sort.each { |r| puts "    ✗ #{r}" }
    elsif trl_dark.empty?
      puts "  manifest TRL:   public manifesto §5 layers match their 00_03 §1 modules ✓"
    end
    if blocker_sections.empty?
      puts "  blockers→00_07:  no canon doc hosts a 🛑/✅-archive blocker section ✓"
    else
      puts "  canon docs hosting blocker sections (#{blocker_sections.size}) — HARD, migrate to 00_07:"
      blocker_sections.sort.each { |b| puts "    · #{b}" }
    end
    if toc_drift.empty?
      puts "  ToC sync:       every TOC:AUTO doc matches its headings ✓"
    else
      puts "  ToC DRIFT (#{toc_drift.size}) — run `bin/rails docs:toc`:"
      toc_drift.each { |d| puts "    ✗ #{d}" }
    end
    if fence_unbalanced.empty?
      puts "  fence balance:  every doc has balanced ``` code fences (no in_fence toggle desync) ✓"
    else
      puts "  UNBALANCED CODE FENCES (#{fence_unbalanced.size}) — an unclosed ``` desyncs every fence-aware guard + truncates the ToC (DOC-T.45):"
      fence_unbalanced.sort.each { |d| puts "    ✗ #{d}" }
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
      puts "  Lorenz formula: no β `8.0/3.0` re-stated outside owner (03_04 §1.2) ✓"
    else
      puts "  LORENZ-FORMULA DRIFT (#{lorenz_drift.size}) — σ/ρ/β values are owned by 03_04 §1.2:"
      lorenz_drift.sort.each { |d| puts "    ✗ #{d}" }
    end
    if tl_chain_hash.empty?
      puts "  TL chain_hash: no false telemetry_logs.chain_hash claim (Merkle leaf = 05_02 §E.60) ✓"
    else
      puts "  TELEMETRY_LOGS.CHAIN_HASH DRIFT (#{tl_chain_hash.size}) — no such column; Merkle leaf is Z-based (05_02 §E.60):"
      tl_chain_hash.sort.each { |d| puts "    ✗ #{d}" }
    end
    if bio_potential.empty?
      puts "  bio_potential:  rejected vocabulary absent as a routing metric (ARCH.11) ✓"
    else
      puts "  BIO_POTENTIAL AS METRIC (#{bio_potential.size}) — ADR rejected it (observer-effect, 00_07 ARCH.11):"
      bio_potential.sort.each { |d| puts "    ✗ #{d}" }
    end
    if gp_clamp.empty?
      puts "  growth_points:  no retired GP formula (`10,63` / `reward / 2` / `50 - deviation`) outside owner (03_04 §4.3) ✓"
    else
      puts "  GROWTH_POINTS FORMULA DRIFT (#{gp_clamp.size}) — [E.63] live form is `metabolic_health(delta_t)` (03_04 §4.3):"
      gp_clamp.sort.each { |d| puts "    ✗ #{d}" }
    end
    if statusbyte_drift.empty?
      puts "  StatusByte:     no retired pre-FW.29 6-bit layout (`<<6` / `0x3F` / bits 7..6) outside owner ✓"
    else
      puts "  STATUSBYTE LAYOUT DRIFT (#{statusbyte_drift.size}) — post-FW.29 = [PanicFlag:1|Status:2|GP:5], pack (status<<5)|gp, mask 0x1F (03_04 §4.3/§4.4 + wire 03_05 §2.1):"
      statusbyte_drift.sort.each { |d| puts "    ✗ #{d}" }
    end
    if mem_links.empty?
      puts "  memory links:     no [[wiki-link]] into out-of-repo memory ✓"
    else
      puts "  MEMORY LINKS (#{mem_links.size}) — canon must not link to memory/ (outside the repo):"
      mem_links.sort.each { |d| puts "    ✗ #{d}" }
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
    failed << "TRL exemption whose page no longer exists (inherited immunity)" unless trl_exempt_dead.empty?
    failed << "owner/exempt constant naming a doc number that no longer exists (inherited immunity)" unless exempt_dead.empty?
    failed << "TRL stated on a declared non-technology page (00_03 §1 category error)" unless trl_misapplied.empty?
    failed << "TRL matrix doc unresolved — 3 TRL gates did not run" unless trl_dark.empty?
    failed << "TRL ranges in 00_03 §1 matrix" unless trl_ranges.empty?
    failed << "TRL band inconsistency (doc TRL vs 00_03 §1 module band)" unless trl_band.empty?
    failed << "manifest TRL drift (PUBLIC manifesto §5 vs 00_03 §1)" unless manifest_trl.empty?
    failed << "ToC drift (run docs:toc)" unless toc_drift.empty?
    failed << "canon docs hosting blocker sections (→ 00_07)" unless blocker_sections.empty?
    failed << "docs missing the standard skeleton" unless conformance.empty?
    failed << "RTC register-map drift (availability claimed outside 03_01)" unless rtc_drift.empty?
    failed << "phantom RTC register DR>19 (STM32WLE5JC has only DR0..DR19)" unless rtc_phantom.empty?
    failed << "Lorenz-formula drift (β re-stated outside 03_04 §1.2)" unless lorenz_drift.empty?
    failed << "telemetry_logs.chain_hash drift (no such column; Merkle leaf = 05_02 §E.60)" unless tl_chain_hash.empty?
    failed << "rejected vocabulary `bio_potential` used as a routing metric (ARCH.11)" unless bio_potential.empty?
    failed << "retired growth_points clamp `(…,10,63)` (FW.29-PACK → 03_04 §4.3)" unless gp_clamp.empty?
    failed << "retired pre-FW.29 StatusByte bit-layout (6-bit `<<6`/`0x3F`/bits 7..6 outside owner)" unless statusbyte_drift.empty?
    failed << "deprecated SSOT terms present" unless deprecated.empty?
    failed << "memory wiki-links in canon" unless mem_links.empty?
    failed << "anchor dimension drift (superseded flange/Zone2 range outside 01_01 §1 freeze)" unless anchor_dim.empty?
    failed << "thermal-stress drift (superseded HW.3.IS SF/P_c number outside 01_01 §4.2 / the report)" unless thermal_drift.empty?
    failed << "unbalanced code fences (unclosed ``` desyncs fence-aware guards + ToC — DOC-T.45)" unless fence_unbalanced.empty?
    failed << "superseded term in front-matter (🎯/Статус names a reversed decision)" unless superseded_fm.empty?
    failed << "tokenomics/carbon rate restated outside One-Home (05_03/00_04)" unless rate_drift.empty?
    failed << "rate-guard anchor stale (home re-priced, regex not — DOC-T.40)" unless rate_anchor.empty?
    failed << "rate-guard home DECLARED but never met in the scan — guard did not run (DOC-T.40/84)" if rate_homes_missing.any?
    failed << "solc/pragma version restated outside One-Home (05_03; code = foundry.toml)" unless solc_drift.empty?
    failed << "canonical source-block drift (pinned code block changed → reconcile mirrors + `rake docs:repin`)" unless block_drift.empty?
    failed << "AI-vendor name restated outside One-Home (00_06 §5 roster; use roles)" unless ai_vendor.empty?
    failed << "bare code-span `NN_NN §X` refs (should be `[`…`](Doc)` links)" unless bare_refs.empty?
    failed << "bare code-span `NN_NN` doc-ids (should be `[`…`](Doc)` links)" unless bare_doc.empty?
    failed << "link label↔href mismatches" unless label_drift.empty?
    failed << "doc-id link labels not in code-span form (00_06 §1)" unless xref_form.empty?
    failed << "§-after-link refs (DOC-T.16 — fold §X into the link label)" unless sec_after_link.empty?
    failed << "canon §-refs (numbered `NN_NN §X` not resolving to a heading)" unless canon_secrefs.empty?
    failed << "dangling #anchors (fragment ≠ heading slug)" unless dangling_anchors.empty?
    failed << "stale external docs/NN_NN refs (.github / root *.md / source)" unless ext_drift.empty?
    failed << "volatile source line-refs `*.c`/`*.h`/`*.rb` (DOC-T.15 — cite symbol/#define)" unless src_line_refs.empty?
    failed << "cited spec paths that do not exist (DOC-T.84 — canon names a guard by a dead name)" unless cited_specs.empty?
    failed << "magic-marker hex ≠ BE/LE ASCII of its quoted name (DOC-T.46)" unless magic_drift.empty?
    failed << "§-section label ≠ any heading in its linked target (DOC-T.48)" unless suspect.empty?
    abort("docs:check_refs FAILED — #{failed.join(', ')}") unless failed.empty?
  end

  desc "Re-pin canonical source-block SHAs in lib/canonical_block_pins.yml (run AFTER reconciling the mirrors)"
  task :repin do
    repo_root = File.expand_path("../..", __dir__)
    pins_path = File.join(repo_root, "lib", "canonical_block_pins.yml")
    pins = YAML.safe_load_file(pins_path) || {}
    changed = 0
    pins.each do |key, cfg|
      src = File.join(repo_root, cfg["source"].to_s)
      abort("docs:repin — source #{cfg['source']} not found") unless File.exist?(src)
      sha, missing = DocsLinter.canonical_block_sha(File.read(src), Array(cfg["consts"]))
      abort("docs:repin — #{key} pinned const(s) absent: #{missing.join(', ')}") unless missing.empty?
      next if cfg["sha256"].to_s == sha

      puts "  re-pinned #{key}: #{cfg['sha256'].to_s.empty? ? '(unpinned)' : cfg['sha256'][0, 12]}… → #{sha[0, 12]}…"
      cfg["sha256"] = sha
      cfg["repinned"] = Time.now.strftime("%Y-%m-%d")
      changed += 1
    end
    if changed.zero?
      puts "  canonical pins already current ✓"
    else
      # YAML.dump serialises DATA only — every comment in the file is lost, and the
      # SPDX header is a comment. Without this re-insert the rewrite silently strips
      # it and `spdx_headers.rb --check` (separate HARD gate) reds the Docs lane.
      File.write(pins_path, YAML.dump(pins).sub(/\A---\n/, "---\n# SPDX-License-Identifier: AGPL-3.0-or-later\n"))
      puts "  wrote #{changed} pin(s) → lib/canonical_block_pins.yml (verify diff before commit)"
    end
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
