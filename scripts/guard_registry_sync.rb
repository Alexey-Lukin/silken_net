#!/usr/bin/env ruby
# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Guard-registry ⟷ code sync gate (DOC-T.40).
#
# The 00_06 §3 drift-prevention registry is itself a hand-written mirror of the
# CI gates — and it rots strictly one-way: new guards land in docs.yml /
# docs.rake / tracker.rake and never get a §3 row (canonical_block_drift — a
# HARD gate — had zero mentions; scc_rate/queen_energy_budget --assert none at
# all). This gate closes the loop:
#
#   A. every `run:` step of the docs.yml `docs_check` job appears VERBATIM in
#      the §3 command column (a wired gate must be registered);
#   B. every `failed <<` label in docs.rake and every Tracker::Dashboard guard
#      called by tracker.rake maps to a §3 row — via the curated maps below
#      (deliberate tripwire, like DEPRECATED_TERMS: a NEW label/guard fails
#      here until it gets a §3 row + a map entry; a RETIRED one leaves a dead
#      map entry that fails too);
#   C. every file path / script name cited in §3 exists on disk (a registry
#      row must not point at a deleted engine);
#   D. parity of the "decorative guard" class: ssot_guard.yml `paths:` ⟷ its
#      embedded `mappings` array (held only by a ⚠️ comment before), every
#      canonical_block_pins.yml source ⊆ the docs.yml `changes` filter (a
#      pinned source outside the filter means the HARD pin-gate silently does
#      not run on the PR that breaks it — the bio_contract.rb hole), every
#      ruby_version_sync mirror + its SSOT ⊆ the same filter (OPS.13 — the
#      Dockerfile/Gemfile bump must trigger the parity gate, not dodge it),
#      and every pin KEY named in the §3 pin-inventory row (a third pin must
#      not leave the row silently stale);
#   E. the REVERSE of A (DOC-T.40 tail): a §3 row may CLAIM a command / a
#      workflow home that the job never runs — the class DOC-T.41 caught by
#      hand in SECURITY_ASSURANCE_CASE ("cppcheck (MISRA) — all gating CI"
#      with no CI call). Every `cmd` (…wf.yml…) pair in the command column
#      must find cmd inside that workflow's run-steps, and every command span
#      must live in SOME workflow unless the row is marked advisory/on-demand.
#      🔴 DECLARED CEILING (moved from the 00_06 §3 row, 2026-08-10 — its only
#      home): a row whose command column carries NO span matching `cmd_span_re`
#      is skipped in SILENCE (`next if cmds.empty?`). So the very class E exists
#      to catch — "declared gating with no CI call" — survived INSIDE this
#      registry, in the row whose command was a doc-ref plus a `bin/rails runner`
#      one-liner. A check that narrows its own subject BY SHAPE always keeps a
#      genre it cannot see; name that genre here, or the green run reads as full
#      coverage of the column.
#
# Pure Ruby (yaml stdlib only, no Rails). Run: ruby scripts/guard_registry_sync.rb
# Exit 0 = in sync; exit 1 = drift (lists the divergence). Method/why → docs/00_06 §3.

require "yaml"
require_relative "ruby_version_sync"

ROOT          = File.expand_path("..", __dir__)
REGISTRY_DOC  = File.join(ROOT, "docs/00_06_SSOT_Documentation_Standard.md")
DOCS_WORKFLOW = File.join(ROOT, ".github/workflows/docs.yml")
SSOT_GUARD_WF = File.join(ROOT, ".github/workflows/ssot_guard.yml")
DOCS_RAKE     = File.join(ROOT, "lib/tasks/docs.rake")
TRACKER_RAKE  = File.join(ROOT, "lib/tasks/tracker.rake")
PINS_YML      = File.join(ROOT, "lib/canonical_block_pins.yml")

# docs.rake `failed <<` label → distinctive §3-row anchor substring.
DOCS_RAKE_LABELS = {
  "dangling doc links"                                                                     => "dangling `NN_NN` doc-links",
  "✅ Статус docs without a TRL"                                                            => "кожен док з `## ✅ Статус` декларує TRL",
  "TRL matrix doc unresolved — 3 TRL gates did not run"                                    => "TRL source lantern",
  "TRL stated on a declared non-technology page (00_03 §1 category error)"                 => "TRL applicability",
  "TRL exemption whose page no longer exists (inherited immunity)"                          => "TRL applicability",
  "owner/exempt constant naming a doc number that no longer exists (inherited immunity)"    => "exemption subject",
  "TRL ranges in 00_03 §1 matrix"                                                          => "одинарне 1-9",
  "TRL band inconsistency (doc TRL vs 00_03 §1 module band)"                               => "TRL range-consistency",
  "manifest TRL drift (PUBLIC manifesto §5 vs 00_03 §1)"                                    => "manifest TRL parity",
  "ToC drift (run docs:toc)"                                                               => "ToC sync",
  "unbalanced code fences (unclosed ``` desyncs fence-aware guards + ToC — DOC-T.45)"      => "fence balance",
  "canon docs hosting blocker sections (→ 00_07)"                                          => "blocker-hygiene",
  "docs missing the standard skeleton"                                                     => "standard-conformance",
  "RTC register-map drift (availability claimed outside 03_01)"                            => "RTC reg-map drift",
  "phantom RTC register DR>19 (STM32WLE5JC has only DR0..DR19)"                            => "RTC phantom register",
  "Lorenz-formula drift (β re-stated outside 03_04 §1.2)"                                  => "Lorenz-formula drift",
  "telemetry_logs.chain_hash drift (no such column; Merkle leaf = 05_02 §E.60)"            => "telemetry_logs.chain_hash drift",
  "rejected vocabulary `bio_potential` used as a routing metric (ARCH.11)"                  => "bio_potential` як МЕТРИКА",
  "retired growth_points clamp `(…,10,63)` (FW.29-PACK → 03_04 §4.3)"                      => "growth_points clamp drift",
  "retired pre-FW.29 StatusByte bit-layout (6-bit `<<6`/`0x3F`/bits 7..6 outside owner)"    => "StatusByte layout",
  "deprecated SSOT terms present"                                                          => "deprecated terms (Ruthless Pruning)",
  "memory wiki-links in canon"                                                             => "memory wiki-link у каноні",
  "anchor dimension drift (superseded flange/Zone2 range outside 01_01 §1 freeze)"         => "anchor dimension drift",
  "thermal-stress drift (superseded HW.3.IS SF/P_c number outside 01_01 §4.2 / the report)" => "thermal-stress One-Home",
  "superseded term in front-matter (🎯/Статус names a reversed decision)"                   => "superseded term in front-matter",
  "tokenomics/carbon rate restated outside One-Home (05_03/00_04)"                         => "tokenomics/carbon rate One-Home",
  "rate-guard anchor stale (home re-priced, regex not — DOC-T.40)"                          => "rate-guard self-anchor",
  "rate-guard home DECLARED but never met in the scan — guard did not run (DOC-T.40/84)" => "rate-home lantern",
  "customer-facing поріг без маркера DAO-мутабельності (SLASH-1)"                            => "customer-facing поріг",
  "solc/pragma version restated outside One-Home (05_03; code = foundry.toml)"             => "solc/pragma version One-Home",
  "canonical source-block drift (pinned code block changed → reconcile mirrors + `rake docs:repin`)" => "canonical source-block pin",
  "AI-vendor name restated outside One-Home (00_06 §5 roster; use roles)"                  => "AI-vendor name One-Home",
  "bare code-span `NN_NN §X` refs (should be `[`…`](Doc)` links)"                          => "bare §-ref → link",
  "bare code-span `NN_NN` doc-ids (should be `[`…`](Doc)` links)"                          => "bare doc-id → link",
  "link label↔href mismatches"                                                             => "link label↔href mismatch",
  "doc-id link labels not in code-span form (00_06 §1)"                                    => "cross-ref label single-form",
  "§-after-link refs (DOC-T.16 — fold §X into the link label)"                             => "§-after-link → fold",
  "canon §-refs (numbered `NN_NN §X` not resolving to a heading)"                          => "canon §-ref resolution",
  "dangling #anchors (fragment ≠ heading slug)"                                            => "#anchor resolution",
  # Другий ДІАЛЕКТ того самого рядка §3 (path-форма поза `docs/`, OPS.32): один рушій
  # слагів, два читачі — тож і анкор реєстру спільний, окремого рядка це не потребує.
  "dead #anchors outside docs/ (runbook_url & friends — OPS.32)"                            => "#anchor resolution",
  "stale external docs/NN_NN refs (.github / root *.md / source)"                          => "external doc-path",
  "volatile source line-refs `*.c`/`*.h`/`*.rb` (DOC-T.15 — cite symbol/#define)"          => "source line-ref drift",
  "magic-marker hex ≠ BE/LE ASCII of its quoted name (DOC-T.46)"                            => "magic-marker hex",
  "§-section label ≠ any heading in its linked target (DOC-T.48)"                            => "§-section label drift",
  "cited spec paths that do not exist (DOC-T.84 — canon names a guard by a dead name)"      => "cited spec path"
}.freeze

# tracker.rake guard method (Tracker::Dashboard.<name>) → §3-row anchor.
TRACKER_GUARDS = {
  "duplicate_ids"                => "whole-file global uniqueness",
  "issues"                       => "meta-line conformance",
  "dangling_refs"                => "canon-ref resolution",
  "section_dangling_refs"        => "§-section resolution",
  "file_section_dangling_refs"   => "whole-file 00_07 §-ref",
  "section_home_violations"      => "section↔canon-home",
  "orphan_item_violations"       => "item visibility",
  "inbound_ref_violations"       => "inbound 00_07 item-ref",
  "inbound_ref_population"       => "inbound 00_07 item-ref",
  "inbound_prose_ref_violations" => "prose 00_07 ID-ref",
  "chem_note_ref_violations"     => "CHEM.N in-silico note-ref",
  "chem_note_ids"                => "CHEM.N in-silico note-ref",
  "chem_ambiguous_token_lines"   => "CHEM.N phantom-def hygiene",
  "inline_residual_runon"        => "residual run-on",
  "verdict_lead_violations"      => "verdict-lead",
  "labour_split_lead"            => "labour-split lead",
  "meta_form_violations"         => "meta-line form",
  "cluster_marker_violations"    => "дім-кластер marker",
  "bench_tag_violations"         => "bench-session tag symmetry",
  "stale_who"                    => "stale WHO",
  "understated_who"              => "understated WHO",
  # [DOC-T.73] Обидва імені мапляться в ОДИН §3-рядок: перевірка та її ліхтар —
  # одна вісь, і розводити їх на два рядки реєстру означало б обіцяти два гейти.
  "priority_order_violations"    => "priority order",
  "priority_ordered_sections"    => "priority order",
  # [DOC-T.92] Той самий принцип «перевірка + її ліхтар = ОДНА вісь, один рядок».
  "residual_lead_form_violations" => "residual lead-form",
  "residual_lead_population"      => "residual lead-form"
}.freeze
# Non-guard Dashboard calls in tracker.rake (parsing/reporting helpers).
TRACKER_HELPERS = %w[parse open_items].freeze

# DOC-T.44 (CHECK A2): canon↔code / config-mirror gates that run OUTSIDE docs.yml.
# CHECK A scans docs.yml ONLY, so a gate wired in another workflow rots its §3 row
# one-way — exactly how test_doc_cache_sync lost its row. Curated allow-list (NOT
# every ci.yml step — most are build/test/lint/fuzz, indistinguishable from a
# registry gate by machine): each cmd must have a §3 row AND still run in its named
# workflow. A NEW canon↔code gate outside docs.yml → add it here + a §3 row (else no
# CHECK sees it); a RETIRED one → dead map entry fails. Scope-ceiling → 00_06 §3 note.
CANON_CODE_GATES_OUTSIDE_DOCS = {
  "ci.yml" => [
    "check_firmware_tables.py", "check_bytecode.py", "gen_bytecode.sh --check",
    "sdl_consistency_check.rb", "deploy_secret_scan.rb"
  ],
  "ml_smoke.yml"        => [ "emit_c --check" ],
  "in_silico_smoke.yml" => [ "test_doc_cache_sync.py", "conda-lock lock --check-input-hash" ],
  # TEST.14: конвенція `testRevert_*` живе в CLAUDE.md §8 — тобто це canon↔code
  # дзеркало, а не build/test-крок, і саме тому воно тут. ⚠️ Сусідній last-admin
  # гейт того ж job'а свідомо лишається ПОЗА мапою: він inline-shell без власного
  # файлу, тож «cmd, що мусить бігти» для нього не має стабільної цитати.
  "solidity_audit.yml"  => [ "solidity_test_naming_check.rb" ]
}.freeze

# §3 slice of 00_06 (from the "3. Drift-prevention" h2 to the next h2).
reg_lines = File.readlines(REGISTRY_DOC)
start = reg_lines.index { |l| l.start_with?("## ") && l.include?("3. Drift-prevention") } or
  abort("guard_registry_sync: cannot locate the §3 h2 in 00_06")
rest     = reg_lines[(start + 1)..]
stop     = rest.index { |l| l.start_with?("## ") } || rest.size
registry = rest[0...stop].join

errors = []

# ── ЛІХТАР НА ВЛАСНУ МНОЖИНУ §3 (2026-08-15) ────────────────────────────────
# CHECK E нижче — ЄДИНИЙ, хто читає §3 ПОРЯДКОВО, і він мовчить у чотири боки,
# кожен із яких лишає EXIT 0:
#   (a) таблиця перестала бути pipe-таблицею → `next unless start_with?("|")`
#       не пускає в тіло ЖОДНОГО рядка, `claimed` падає в нуль, скрипт друкує ✓;
#   (b) дописана 4-та колонка → `cols[-2]` зсувається В УСІХ рядках одразу;
#   (c) загублений хвостовий `|` (або неекранований `|` у комірці) → `cols[-2]`
#       стає колонкою ОПИСУ, і рядок ще й САМОМАСКУЄТЬСЯ: опис, що згадує
#       advisory, вмикає скіп рядка, який насправді HARD;
#   (d) команда, винесена з останньої комірки → `next if cmds.empty?` (оголошена
#       стеля вище; тут вона нарешті ще й ВИМІРЮЄТЬСЯ).
# Тому периметр міряється ТУТ, ДО перевірок: порожній набір знахідок означає
# «чисто» лише коли перевірка ВИКОНАЛАСЬ (§Guard-craft #47).
#
# 🔴 ФОРМА ПОРОГУ — з `scripts/memory_route_check.rb` (SOURCE_FLOOR), і вона
# СВІДОМО не «жорсткий пін» і не «не спадає»: це ПІДЛОГА З ЗАПАСОМ, яку людина
# опускає ВИДИМОЮ правкою. Підстава емпірична, не смакова — за всю історію доку
# рядки §3 зникали РІВНО ОДИН раз (−2 із 90, присуд У-ВЕЙ 2026-08-09), разом із
# кодом, який вони реєстрували. Тобто легітимна втрата мала, рідкісна й
# самопояснювальна, а обвал у нуль — ні. Лічильник call-site'ів тут був би
# помилкою (він карає чесний рефакторинг), лічильник РЯДКІВ РЕЄСТРУ — ні.
ROW_FLOOR   = 60   # data-рядків §3
CLAIM_FLOOR = 20   # пар «команда (workflow)», які бачить CHECK E
PATH_FLOOR  = 50   # файл-токенів, які перевіряє CHECK C

registry_rows = registry.lines
                        .select { |l| l.lstrip.start_with?("|") }
                        .reject { |l| l.include?("| Guard |") || l.match?(/\A\s*\|[\s\-:|]+\|\s*\n?\z/) }

if registry_rows.size < ROW_FLOOR
  errors << "ПЕРИМЕТР §3 СТИСНУВСЯ: розпарсено #{registry_rows.size} data-рядків, підлога #{ROW_FLOOR}. " \
            "Зелений вердикт над стиснутою множиною — не вердикт. Або таблиця перестала бути pipe-таблицею " \
            "(і тоді CHECK E не побачив жодного рядка), або гейти справді зняли — тоді опусти підлогу ТУТ, " \
            "щоб втрата стала видимим рішенням у діфі."
end

# Форма рядка (закриває (b) і (c)): рівно ТРИ колонки ⇒ 5 split-частин
# ("", col1, col2, col3, ""). Екранований `\|` нейтралізується — він легітимний
# усередині комірки; неекранований ламає і рендер, і `cols[-2]`.
registry_rows.each do |row|
  cols = row.chomp.gsub('\\|', " ").split("|", -1)
  next if cols.size == 5

  name = cols[1].to_s.strip[0, 60]
  errors << "§3 рядок «#{name}» має #{cols.size - 2} колонок замість 3 — CHECK E читає команду як " \
            "`cols[-2]`, тож зсув робить його вердикт беззмістовним МОВЧКИ. Причина зазвичай одна: " \
            "неекранований `|` усередині комірки (пиши `\\|`) або загублений хвостовий `|`."
end

# ── A. docs_check run-steps ⊆ §3 command column (verbatim) ──────────────────
docs_wf = YAML.safe_load_file(DOCS_WORKFLOW)
steps   = docs_wf.dig("jobs", "docs_check", "steps") or
  abort("guard_registry_sync: cannot read jobs.docs_check.steps from docs.yml")
run_cmds = steps.filter_map { |s| s["run"]&.strip }
run_cmds.each do |cmd|
  errors << "docs_check run-step not registered in 00_06 §3: `#{cmd}`" unless registry.include?(cmd)
end

# ── B. rake guards ↔ §3 rows (curated maps, both directions) ────────────────
labels = File.read(DOCS_RAKE).scan(/failed << "([^"]+)"/).flatten
(labels - DOCS_RAKE_LABELS.keys).each do |l|
  errors << "NEW docs.rake failed-label without a §3 row / map entry: #{l.inspect}"
end
(DOCS_RAKE_LABELS.keys - labels).each do |l|
  errors << "dead map entry — label no longer in docs.rake: #{l.inspect}"
end

guards = File.read(TRACKER_RAKE).scan(/Tracker::Dashboard\.(\w+)/).flatten.uniq - TRACKER_HELPERS
(guards - TRACKER_GUARDS.keys).each do |g|
  errors << "NEW tracker.rake guard without a §3 row / map entry: Tracker::Dashboard.#{g}"
end
(TRACKER_GUARDS.keys - guards).each do |g|
  errors << "dead map entry — guard no longer called by tracker.rake: #{g}"
end

(DOCS_RAKE_LABELS.values | TRACKER_GUARDS.values).each do |anchor|
  errors << "§3 row missing — anchor not found in 00_06 §3: #{anchor.inspect}" unless registry.include?(anchor)
end

# ── C. every file cited in §3 exists on disk ────────────────────────────────
BARE_NAME_DIRS = "{app,scripts,tools,lib,bin,spec,firmware,docs,.github}"
# Названа змінна, а не інлайн-скан: без неї CHECK C не мав ЧОГО пінити, і його
# охоплення могло тихо стиснутись — success-рядок його не друкував узагалі.
path_tokens = registry.scan(%r{[\w./*-]*\w\.(?:rb|py|sh|yml|rake)}).uniq
if path_tokens.size < PATH_FLOOR
  errors << "CHECK C стиснувся: #{path_tokens.size} файл-токенів у §3, підлога #{PATH_FLOOR} — " \
            "«жоден шлях не битий» над порожньою множиною означає «шляхів не знайдено»."
end
path_tokens.each do |token|
  found =
    if token.include?("*")
      Dir.glob(File.join(ROOT, token)).any?
    elsif token.include?("/")
      File.exist?(File.join(ROOT, token))
    else
      Dir.glob(File.join(ROOT, BARE_NAME_DIRS, "**", token)).any?
    end
  errors << "§3 cites `#{token}` which does not exist on disk" unless found
end

# ── D1. ssot_guard.yml paths: ⟷ embedded mappings parity ────────────────────
sg_text = File.read(SSOT_GUARD_WF)
sg_yaml = YAML.safe_load(sg_text)
sg_on   = sg_yaml["on"] || sg_yaml[true] # YAML 1.1 parses bare `on:` as boolean true
sg_paths = (sg_on.dig("pull_request", "paths") || []).map { |g| g.sub(/\*\*\z/, "") }.sort
sg_mappings = sg_text.scan(%r{pattern:\s*/\^(.+?)/,}).flatten.map { |p| p.gsub('\\/', "/") }.sort
if sg_paths != sg_mappings
  (sg_paths - sg_mappings).each { |p| errors << "ssot_guard.yml paths: has `#{p}**` with NO mappings pattern (run starts, area invisible → green)" }
  (sg_mappings - sg_paths).each { |p| errors << "ssot_guard.yml mappings has /^#{p}/ with NO paths: glob (run never starts for that area)" }
end

# ── D2. pinned sources ⊆ docs.yml changes-filter (anti-decorative-guard) ────
filters_raw = (docs_wf.dig("jobs", "changes", "steps") || [])
              .filter_map { |s| s.dig("with", "filters") }.first or
  abort("guard_registry_sync: cannot read the changes-filter from docs.yml")
filter_globs = YAML.safe_load(filters_raw)["docs"]
glob_res = filter_globs.map do |g|
  re = Regexp.escape(g).gsub('\*\*', "DOUBLESTAR").gsub('\*', "[^/]*").gsub("DOUBLESTAR", ".*")
  Regexp.new("\\A#{re}\\z")
end
pins = YAML.safe_load_file(PINS_YML) || {}
pin_inputs = pins.values.map { |cfg| cfg["source"].to_s } +
             [ "lib/canonical_block_pins.yml" ] +
             RubyVersionSync::MIRRORS.keys + [ RubyVersionSync::SSOT ]
pin_inputs.uniq.each do |src|
  covered = glob_res.any? { |re| re.match?(src) }
  errors << "pinned source `#{src}` NOT covered by the docs.yml changes-filter — the HARD pin-gate is decorative for it" unless covered
end

# ── D3. every pin KEY is named in §3 (inventory tripwire, DOC-T.40) ─────────
pins.each_key do |key|
  errors << "pin `#{key}` (canonical_block_pins.yml) not named in 00_06 §3 — the pin-inventory row went stale" unless registry.include?("`#{key}`")
end

# ── E. §3 command column → workflows (reverse loop of A, DOC-T.40) ──────────
wf_runs = Hash.new do |h, wf|
  path = File.join(ROOT, ".github/workflows", wf)
  h[wf] = if File.exist?(path)
            YAML.safe_load_file(path).fetch("jobs", {}).values
                .flat_map { |j| (j["steps"] || []).filter_map { |s| s["run"] } }.join("\n")
  end
end

# ── A2. canon↔code gates OUTSIDE docs.yml ⊆ §3 (DOC-T.44) ────────────────────
# Forward: each curated gate must be registered in §3 (CHECK A only covers docs.yml).
# Dead-map: each must still run in its named workflow (a retired one fails loudly).
a2_gates = 0
CANON_CODE_GATES_OUTSIDE_DOCS.each do |wf, cmds|
  runs = wf_runs[wf]
  cmds.each do |cmd|
    a2_gates += 1
    errors << "canon↔code gate `#{cmd}` (#{wf}) not registered in 00_06 §3 — a gate outside docs.yml rots one-way (DOC-T.44)" unless registry.include?(cmd)
    if runs.nil?
      errors << "DOC-T.44 A2 map cites workflow #{wf} that does not exist"
    elsif !runs.include?(cmd)
      errors << "DOC-T.44 A2 map cites `#{cmd}` in #{wf}, but no run-step there contains it (retired gate → drop the map entry)"
    end
  end
end

cmd_span_re = /\A(?:[A-Z0-9_]+=\S+\s+)*(?:bin\/|ruby |python|make )/
all_wf_runs = nil
claimed = 0
registry.each_line do |line|
  next unless line.lstrip.start_with?("|")

  cols    = line.split("|")
  cmd_col = cols[-2].to_s
  # The advisory skip must read the row's ROLE, never a MENTION of the word.
  # A non-CI row declares itself in one of two places: the command column, or a
  # leading `_(advisory, on-demand …)_` italic opening the description. The same
  # token inside the prose is EXPLANATION — and the row that defines axis E has
  # to spell it out by construction, so it was excluding itself from the axis it
  # documents. Measured 2026-08-10: of 13 rows carrying the token, 6 declare a
  # role and **7 were HARD rows switched off by their own prose** — among them
  # this script's row, the phantom-ID gate and the DCO gate. Class → §Guard-craft
  # #7 (a mask that turns the gate off while the comment beside it justifies a
  # different problem).
  desc_col = cols[2].to_s.strip
  next if cmd_col.match?(/advisory|on-demand|НЕ CI/i) || desc_col.start_with?("_(")

  cmd_col.scan(/`([^`]+)`\s*\(([^)]*)\)/) do |cmd, paren|
    # a workflow home is cited by BARE name (docs.yml, ci.yml); a path segment
    # (`lib/canonical_block_pins.yml`) is a config file, not a workflow claim
    paren.scan(%r{(?<![\w./-])[\w-]+\.yml}).each do |wf|
      claimed += 1
      runs = wf_runs[wf]
      if runs.nil?
        errors << "§3 claims `#{cmd}` runs in #{wf}, but that workflow does not exist"
      elsif !runs.include?(cmd)
        errors << "§3 claims `#{cmd}` runs in #{wf}, but no run-step there contains it (phantom gate claim)"
      end
    end
  end

  cmds = cmd_col.scan(/`([^`]+)`/).flatten.grep(cmd_span_re)
  next if cmds.empty?

  all_wf_runs ||= Dir[File.join(ROOT, ".github/workflows/*.yml")]
                  .map { |p| wf_runs[File.basename(p)] }.join("\n")
  unless cmds.any? { |c| all_wf_runs.include?(c) }
    errors << "§3 row claims #{cmds.inspect} but NO workflow runs any of them (mark the row advisory/on-demand, or drop it)"
  end
end

if claimed < CLAIM_FLOOR
  errors << "CHECK E ОСЛІП: зібрано #{claimed} пар «команда (workflow)», підлога #{CLAIM_FLOOR}. " \
            "Це ЄДИНА порядкова перевірка §3, і вона віддає нуль мовчки — де-таблиця, зсунута колонка " \
            "чи загублений хвостовий `|` дають рівно цей симптом. Спершу перевір форму таблиці, " \
            "а підлогу опускай лише тоді, коли реєстр справді зменшили."
end

# ── F. «прожени X» у прозі не сміє продавати ПІДМНОЖИНУ як смугу (OPS.25) ───
# Дефект, що це купив: чекліст «Before merge» у скілі тримав рукописний перелік
# девʼяти гейтів БЕЗ `spdx_headers` — того, що клав `main` тричі; а плейбук
# архівації приписував верифікацію двома кроками у секції, яка зветься «GATE».
# Джерело формули — `00_06 §3` + шапка `docs.yml`, тож периметр СВІДОМО ширший
# за `.claude/**`: полагодити копії й лишити джерело = гарантований рецидив.
#
# 🔴 Якір — форма ВИКЛИКУ (`ruby scripts/docs_check.rb`), не імʼя референта.
# Виміряно: якір на будь-який синонім (`docs:check_refs`/`tracker:check`) дав би
# 15 хибних — `guard-craft.md` і таблиці скіла НАЗИВАЮТЬ ці гейти в педагогічній
# прозі, і це легітимно. Виклик = імператив «ось як я перевіряю»; назва = опис.
# ⚠️ Стеля: перейменують alias — якір осліпне мовчки, тому він деривований із
# наявного файлу (нижче), а не написаний літералом удруге.
FAST_ALIAS   = File.basename(Dir[File.join(ROOT, "scripts/docs_check.rb")].first.to_s)
BAND_ALIAS   = File.basename(Dir[File.join(ROOT, "scripts/docs_band.rb")].first.to_s)
CLAIM_WINDOW = 6

if FAST_ALIAS.empty? || BAND_ALIAS.empty?
  errors << "CHECK F: не знайдено scripts/docs_check.rb або scripts/docs_band.rb — якір сліпий, не мовчазний"
else
  claim_files = Dir[File.join(ROOT, ".claude/**/*.{md,sh}")] +
                [ REGISTRY_DOC, DOCS_WORKFLOW ]
  claim_files.each do |path|
    next unless File.file?(path)

    lines = File.readlines(path)
    lines.each_with_index do |line, i|
      next unless line.include?(FAST_ALIAS)

      lo = [ i - CLAIM_WINDOW, 0 ].max
      hi = [ i + CLAIM_WINDOW, lines.size - 1 ].min
      next if lines[lo..hi].any? { |l| l.include?(BAND_ALIAS) }

      rel = path.sub("#{ROOT}/", "")
      errors << "CHECK F #{rel}:#{i + 1} — кличе `#{FAST_ALIAS}` (два кроки джоби) без згадки " \
                "`#{BAND_ALIAS}` у ±#{CLAIM_WINDOW} рядках: підмножина продається як смуга (OPS.25)"
    end
  end
end

# ── report ──────────────────────────────────────────────────────────────────
if errors.empty?
  puts "guard_registry_sync ✓ — 00_06 §3 ⟷ CI gates (#{run_cmds.size} run-steps, " \
       "#{labels.size} docs.rake labels, #{guards.size} tracker guards, " \
       "#{sg_paths.size} ssot_guard areas, #{pin_inputs.uniq.size} pinned inputs, " \
       "#{a2_gates} outside-docs.yml A2 gates, #{claimed} reverse §3→workflow claims; " \
       "периметр: #{registry_rows.size} §3-рядків ≥ #{ROW_FLOOR} · #{path_tokens.size} шляхів ≥ #{PATH_FLOOR} · " \
       "#{claimed} claims ≥ #{CLAIM_FLOOR})"
  exit 0
else
  warn "guard_registry_sync ✗ — guard-registry ↔ code drift (DOC-T.40):"
  errors.each { |e| warn "  · #{e}" }
  exit 1
end
