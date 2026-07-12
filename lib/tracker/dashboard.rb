# frozen_string_literal: true

# [00_07 DRY tooling — #3 item-form contract + drift guards]
#
# Parses the undone-task registry (§-module + 🔀 cross-cutting sections) of
# docs/00_07_Action_Plan_Tracker.md and lints it: duplicate IDs, item-form
# conformance (priority + WHO + STAGE + canon-ref), §-ref / section↔home /
# inbound-ref resolution, and run-on / verdict-lead / meta-line form — the
# "one fact, one place" principle made mechanical (user). The 🚦 do-now view is a
# hand-curated Critical Path in the doc (DOC-T.16); there is no auto-render.
#
# Pure Ruby (no Rails) — runnable from a rake task or CI without booting the app.
module Tracker
  class Dashboard
    DEFAULT_PATH = File.expand_path("../../docs/00_07_Action_Plan_Tracker.md", __dir__)
    DOCS_DIR = File.expand_path("../../docs", __dir__)

    # #### items under these sections feed the dashboard (mirror canon modules).
    REGISTRY_SECTION = /^## (?:§|🔀)/
    # Non-actionable / index sections explicitly excluded.
    SKIP_SECTION = /^## (?:🎯|🚦|📌|🗄️)/

    # WHO axis (Projects-V2 "Assigned Agent") — who does the OPEN work.
    # ⚖️ = decision-residual (голова, ⊂ 👤 [DOC-T.33]): a verdict that does NOT
    # reduce to a known action — allowed on checkboxes (phase 1) AND in the
    # meta-line WHO (phase 2, scan-on-section).
    EXECUTORS = { "🤖" => :machine, "👤" => :owner, "⚖️" => :decider }.freeze
    # STAGE axis (Projects-V2 "Shape Up Stage") — lifecycle, SEPARATE from WHO [DOC-T.18].
    # 🟡 (in-progress) and 🔗 (blocked) were wrongly mapped as :blocked EXECUTORS —
    # conflating who-with-status (a 🟡 in-progress item is NOT blocked; it routed to
    # the dashboard's "Заблоковано" bucket). Now STAGE is its own axis; "blocked" in
    # the dashboard = STAGE 🔗, not a WHO.
    # ∅ = vacuous [DOC-T.34]: «нема-що-завершувати» — the premise was refuted /
    # absorbed elsewhere, so there is nothing to activate (≠ 🟢) and nothing to
    # wait on (≠ 🔗); the item stays in place as a closed-canon note.
    STAGES = {
      "⚪" => :not_started, "🟡" => :in_progress, "🟢" => :done_inert,
      "🔗" => :blocked, "🌿" => :far_horizon, "∅" => :vacuous
    }.freeze

    Item = Struct.new(:id, :title, :priority, :executors, :stage, :canon, :section_modules, keyword_init: true)

    # `## §NN`-section module set: `§03/§05`→["03","05"]; sub-letter ignored, so
    # `§01a`/`§08b`→["01"]/["08"] (multiple sub-sections share a module — §08a/b/c).
    SECTION_NUMS = /§\s*(\d{2})/
    # #### heading ID — tolerates a leading emoji/✅ run (`#### 🌿 UNI.13a — …`),
    # which a bare `[A-Z]`-anchored match silently dropped (UNI.13a / BIZ.12).
    ITEM_HEAD = /^####\s+(?:[✅\p{So}\p{Sk}\u{FE0F}]+\s+)*([A-Z][A-Za-z0-9]*[.\-][0-9A-Za-z.\-]+)\s+[—-]\s+(.+?)\s*$/

    # --- parse markdown → [Item] ---
    def self.parse(markdown)
      items = []
      current = nil
      in_registry = false
      section_modules = nil

      markdown.each_line do |line|
        if line.start_with?("## ")
          items << current if current
          current = nil
          in_registry = line.match?(REGISTRY_SECTION) && !line.match?(SKIP_SECTION)
          # only `## §NN` headers carry a module set; `## 🔀` cross-cutting → nil (exempt)
          section_modules = line.start_with?("## §") ? line.scan(SECTION_NUMS).flatten : nil
          next
        end
        next unless in_registry

        if (m = line.match(ITEM_HEAD))
          items << current if current
          current = Item.new(id: m[1], title: m[2].sub(/\s*✅\s*\z/, ""), executors: [], section_modules: section_modules)
        elsif current
          if (pr = line[/\*\*(P[0-3])\*\*/, 1])
            current.priority ||= pr
            # meta-line `- **P?** · WHO · STAGE · → canon` carries WHO (executor) on one
            # axis and STAGE (lifecycle) on the other [DOC-T.18]. STAGE is read ONLY here
            # (meta-line), not from `[ ] 🔗 …` residual bullets where 🔗 marks a per-residual
            # block, not the item's stage.
            EXECUTORS.each { |emoji, role| current.executors << role if line.include?(emoji) }
            STAGES.each { |emoji, st| current.stage ||= st if line.include?(emoji) }
          end
          # also pick up executors from unchecked checkbox bullets (HW light-touch items)
          if line.match?(/^\s*-\s*\[ \]/)
            EXECUTORS.each { |emoji, role| current.executors << role if line.include?(emoji) }
          end
          current.canon ||= line[/`(\d{2}_\d{2}[^`]*)`/, 1]
        end
      end
      items << current if current
      items.each { |it| it.executors.uniq! }
      items
    end

    # --- registry table-row IDs (dup-guard blind-spot fix) ---
    # The dup-guard tallies #### heading IDs only; an ID used as BOTH a table-row
    # (e.g. `| DOC-T.12 | … |` in the DOC-drift registry) AND a #### heading slipped
    # through silently (the DOC-T.12 ↔ DOC-T.13 collision). This returns the first-cell
    # ID token of every table row inside the §/🔀 registry sections so the caller
    # can merge them into the dup tally. Same ID shape as `parse`; header/separator
    # rows (no ID in the first cell) and **bold** wrappers are handled.
    # A leading emoji/✅ run is tolerated (`| ✅ OPS.5 |`, `| 🌿 E.59 |`) — the same
    # blind spot that once hid `#### 🌿 UNI.13a`; without it a status-prefixed backlog
    # row was invisible to BOTH the dup tally and inbound-ref resolution.
    # Лідерний emoji/✅-run — єдиний лінійний char-class (НЕ вкладений `(?:[…]+\s*)*`,
    # чий опційний роздільник давав exponential backtracking / ReDoS).
    TABLE_ID_RE = /\A\|[\s✅\p{So}\p{Sk}\u{FE0F}]*\*{0,2}([A-Z][A-Za-z0-9]*[.\-][0-9A-Za-z.\-]+)\*{0,2}\s*\|/

    def self.table_row_ids(markdown)
      in_registry = false
      markdown.each_line.filter_map do |line|
        if line.start_with?("## ")
          in_registry = line.match?(REGISTRY_SECTION) && !line.match?(SKIP_SECTION)
          next
        end
        next unless in_registry

        line.match(TABLE_ID_RE)&.captures&.first
      end
    end

    # --- inbound 00_07 item-ref resolution ---
    # Other docs reference a tracker item as `[`00_07` — <ID>](00_07_…)`. Nothing
    # validated that <ID> is REAL, so `06_02 → 00_07 DOC.5` rotted silently after the
    # item was renamed/removed (the dangling-inbound-ref blind spot the DOC.N namespace
    # work surfaced). `all_item_ids` collects EVERY 00_07 item ID — all #### headings +
    # all table-row first-cells, across ALL sections incl. 📌 Backlog / 🗄️ Архів (NOT
    # section-filtered like parse/table_row_ids, since inbound refs point into those too).
    # `inbound_ref_violations` flags any em-dash ref to a non-existent ID. The captured ID
    # REQUIRES a `.`/`-` separator (`INF.4`, `DOC-T.5`) so a directory-title link
    # (`[`00_07` — Action Plan Tracker](…)`) is NOT a false positive. Pure (caller passes docs_dir).
    ANY_ITEM_HEAD  = /^####\s+(?:[✅\p{So}\p{Sk}\u{FE0F}]+\s+)*([A-Z][A-Za-z0-9]*[.\-][0-9A-Za-z.\-]+)/
    INBOUND_REF_RE = /\[`00_07`\s*[—-]\s*([A-Z][A-Za-z0-9]*[.\-][0-9A-Za-z.\-]+)\]\(00_07/

    def self.all_item_ids(markdown)
      markdown.each_line.filter_map { |l| (l.match(ANY_ITEM_HEAD) || l.match(TABLE_ID_RE))&.captures&.first }
    end

    # --- global ID uniqueness (dup-guard scope widened) ---
    # Every tracker item ID must be unique across the WHOLE file. The earlier tally
    # spanned only the §/🔀 registry sections (parse + table_row_ids), so a 📌 Backlog
    # or 🗄️ Архів row could silently reuse an active ID — exactly the `OPS.5` collision
    # (`#### OPS.5` §07 ↔ `| ✅ OPS.5 |` backlog) that slipped through. Reuses
    # `all_item_ids` (whole-file span, the same source the inbound-ref guard trusts),
    # so "what IDs exist" has one definition. Returns the >1 tally (id => count).
    def self.duplicate_ids(markdown) = all_item_ids(markdown).tally.select { |_, count| count > 1 }

    def self.inbound_ref_violations(docs_dir = DOCS_DIR)
      tracker = File.join(docs_dir, "00_07_Action_Plan_Tracker.md")
      return [] unless File.exist?(tracker)

      valid = all_item_ids(File.read(tracker))
      Dir.glob(File.join(docs_dir, "*.md")).sort.flat_map do |f|
        base = File.basename(f, ".md")
        next [] if base.start_with?("00_07")

        File.read(f).scan(INBOUND_REF_RE).flatten.filter_map do |id|
          "#{base} → `00_07 — #{id}` (no such 00_07 item)" unless valid.include?(id)
        end
      end
    end

    # --- prose ID-list refs after a 00_07 link ---
    # Beyond the `[`00_07` — ID]` directory form, Status lines cite tracker IDs in PROSE
    # right after a 00_07 link: `→ [`00_07`](00_07_…) (S4.3, INF.4, S5.6)`. Nothing
    # validated those, so a WRONG id (`S6.1` Redis where the GCS-bucket `S5.6` was meant)
    # and a ref to a NON-EXISTENT item (`OBS.1` before it had a row) rotted silently — the
    # em-dash inbound gate never saw them. Captures the paren list right after a 00_07 link,
    # extracts full ID tokens (letter-prefix + `.`/`-` + digit; a `X.*` wildcard lacks a
    # digit → skipped naturally), expands `/`-digit families (`INF.3/4/6`), flags any not a
    # real item. Token-shape filtered so prose words / `§X` aren't FPs. Pure (caller passes dir).
    PROSE_LIST_AFTER_LINK = /\]\(00_07_Action_Plan_Tracker[^)]*\)\s*\(([^)]+)\)/
    PROSE_ID_TOKEN        = %r{[A-Z][A-Z0-9]*(?:-[A-Z]+)?[.\-]\d+[A-Za-z]*(?:/\d+)*}

    def self.expand_prose_ids(list)
      list.scan(PROSE_ID_TOKEN).flat_map do |tok|
        segs   = tok.split("/")
        prefix = segs.first[/\A[A-Z][A-Z0-9]*(?:-[A-Z]+)?[.\-]/]
        segs.map { |s| s.match?(/\A\d/) ? "#{prefix}#{s}" : s }
      end
    end

    def self.inbound_prose_ref_violations(docs_dir = DOCS_DIR)
      tracker = File.join(docs_dir, "00_07_Action_Plan_Tracker.md")
      return [] unless File.exist?(tracker)

      valid = all_item_ids(File.read(tracker))
      Dir.glob(File.join(docs_dir, "*.md")).sort.flat_map do |f|
        base = File.basename(f, ".md")
        next [] if base.start_with?("00_07")

        File.read(f).scan(PROSE_LIST_AFTER_LINK).flatten.flat_map do |list|
          expand_prose_ids(list).filter_map do |id|
            "#{base} → `00_07 (#{id})` (no such 00_07 item)" unless valid.include?(id)
          end
        end
      end
    end

    # --- CHEM.N in-silico chemistry-note refs ---
    # The HW.5.IS in-silico chemistry backlog is a bulleted, triaged list (not #### items),
    # so its 31 notes carry their own CHEM.N IDs (`- [ ] **CHEM.6** — …`), standardized from
    # the old ad-hoc `note N` so the refs are guardable like every other 00_07 ID (founder
    # `note N` was unanchored + already restated across 01_03/SUMMARY/L1/scripts →
    # a drift surface). `chem_note_ids` collects the defined set (the checkbox is optional, so
    # the corrected-out / separate-stream bullets count too); `chem_note_ref_violations` flags
    # any CHEM.N in ANOTHER doc (incl. the in_silico protocol subdir → `**/*.md`) that doesn't
    # resolve. Slash-families (`CHEM.20/26`) expand to each member.
    CHEM_REF_RE  = /CHEM\.\d+(?:\/\d+)*/
    CHEM_HEAD_RE = /^\s*[-*]\s*(?:\[[ xX]\]\s*)?(.+?)\s+—\s/   # bullet ID-cluster before the em-dash

    def self.expand_chem(tok)
      tok.split("/").map { |s| s.start_with?("CHEM.") ? s : "CHEM.#{s}" }
    end

    # IDs DEFINED in 00_07 = the leading ID-cluster of a backlog bullet (before the em-dash),
    # so a compound `**CHEM.22** + **CHEM.5** —` yields BOTH, while a CHEM ref that appears in
    # the DESCRIPTION (after the em-dash, e.g. "subsumed by CHEM.29") is NOT mistaken for a def.
    def self.chem_note_ids(markdown)
      markdown.each_line.flat_map do |l|
        next [] unless (m = l.match(CHEM_HEAD_RE)) && m[1].include?("CHEM.")
        m[1].scan(CHEM_REF_RE).flat_map { |t| expand_chem(t) }
      end
    end

    # Phantom-def hygiene: a bare CHEM.N token in a CHECKBOX bullet that has NO em-dash is
    # ambiguous — `chem_note_ids` (em-dash-scoped) reads it as a ref, but a whole-line dup-scan
    # reads it as a second *definition* (how a CHEM.14 dup slipped past the committed guard while
    # a stricter local scan flagged it). Policy: a status/checkbox bullet must not carry a bare
    # CHEM.N — reword, or make it a real `CHEM.N — …` def. Low-FP: only fires on no-em-dash
    # checkbox bullets that mention a CHEM token (legit refs live after the em-dash in a def bullet).
    CHECKBOX_RE = /^\s*[-*]\s*\[[ xX]\]/
    def self.chem_ambiguous_token_lines(markdown)
      markdown.each_line.filter_map do |l|
        next unless l.match?(CHECKBOX_RE)
        next if l.include?("—")   # em-dash present → def/ref position is unambiguous
        ids = l.scan(CHEM_REF_RE).uniq
        next if ids.empty?
        "#{ids.join(', ')} — bare token in a no-em-dash checkbox bullet (reword): #{l.strip[0, 55]}…"
      end
    end

    # Scanned for CHEM.N refs: the canon docs (incl. the in_silico protocol subdir) AND the
    # in_silico scripts (founder: the refs leaked into CODE too). 00_07 is the definer → skipped.
    CHEM_SCAN_GLOBS = [ "docs/**/*.md", "tools/in_silico/scripts/*.py" ].freeze

    def self.chem_note_ref_violations(docs_dir = DOCS_DIR)
      tracker = File.join(docs_dir, "00_07_Action_Plan_Tracker.md")
      return [] unless File.exist?(tracker)

      root  = File.expand_path("..", docs_dir)   # repo root (docs/ parent)
      valid = chem_note_ids(File.read(tracker))
      CHEM_SCAN_GLOBS.flat_map { |g| Dir.glob(File.join(root, g)) }.sort.flat_map do |f|
        next [] if File.basename(f).start_with?("00_07")

        File.read(f).scan(CHEM_REF_RE).flat_map { |tok| expand_chem(tok) }.uniq.filter_map do |id|
          "#{File.basename(f)} → #{id} (no such CHEM note)" unless valid.include?(id)
        end
      end
    end

    # Open = has ≥1 unchecked bullet with a known executor.
    def self.open_items(items) = items.select { |it| it.executors.any? }

    # --- #3 conformance: open items missing priority / canon-ref ---
    def self.issues(items)
      items.filter_map do |it|
        missing = []
        missing << "priority" unless it.priority
        missing << "executor" if it.executors.empty?
        missing << "stage" unless it.stage          # [DOC-T.18] WHO · STAGE both required
        missing << "canon-ref" unless it.canon
        "#{it.id}: missing #{missing.join(', ')}" if missing.any?
      end
    end

    # --- canon-ref resolution [#2]: each → `NN_NN …` must point to a real docs/NN_NN_*.md ---
    def self.dangling_refs(items)
      items.filter_map do |it|
        next unless it.canon

        prefix = it.canon[/\A\d{2}_\d{2}/]
        next unless prefix

        "#{it.id}: canon `#{it.canon}` → no docs/#{prefix}_*.md" if Dir.glob(File.join(DOCS_DIR, "#{prefix}_*.md")).empty?
      end
    end

    # --- §-section validation [#2b, thread C]: a canon-ref `NN_NN §X` whose §X names a
    # section must resolve to a heading in the TARGET doc — catches a tracker pointer left
    # dangling after the section was renamed/removed (the §BLOCKER-N refs orphaned by the
    # blockers→00_07 sweep). Mirrors DocsLinter.section_label_drift: tokens <2 chars (bare
    # §3 — resolve trivially) and meta placeholders (§NN/§N/§X) are skipped. ---
    SECTION_TOKEN = /§\s*([0-9A-Za-zА-Яа-яІіЇїЄє.\-]+)/

    def self.section_dangling_refs(items, docs_dir = DOCS_DIR)
      heads = Dir.glob(File.join(docs_dir, "*.md")).each_with_object({}) do |f, h|
        id = File.basename(f, ".md")[0, 5]
        h[id] = File.readlines(f).grep(/^\#{1,6}\s/).join("\n").downcase if id =~ /\A\d\d_\d\d/
      end
      items.filter_map do |it|
        next unless it.canon

        id = it.canon[/\A\d\d_\d\d/]
        next unless id && heads[id]

        bad = it.canon.scan(SECTION_TOKEN).flatten
                      .reject { |t| t.length < 2 || t.match?(/\A[nxNX]+\z/) }
                      .reject { |t| heads[id].include?(t.downcase) }
        "#{it.id}: `#{it.canon}` → §#{bad.join(', §')} absent in #{id}" unless bad.empty?
      end
    end

    # --- whole-file §-ref resolution [Module-08 §1.N sub-section-collapse, 2026-06-09] ---
    # EVERY `NN_NN §X` ref ANYWHERE in 00_07 — incl. bare code-span refs in 📌 Backlog /
    # 🗄️ Архів table cells + prose — must resolve to a real heading-anchor in the target.
    # section_dangling_refs scans only #### `it.canon` meta-refs, and the bare-§ guard is
    # 00_07-exempt, so ~20 refs orphaned by Taxonomy-v3's §1.x collapse (08_01/08_02 §1.1–
    # §1.8 → §1A/§1B / "Стаття N") rotted unseen. Boundary-aware: a §1.3 ref does NOT
    # falsely resolve against a 2.1.3 heading (the old substring `include?` would). A
    # parent-group ref resolves when its children exist (§4а ⇐ 4а.1..4а.5). Ranges split on
    # -/+///; a lowercase ".x" tail = wildcard placeholder (skipped — real literal subsecs
    # use ".X"); "Стаття N" named refs carry no § → out of scope here.
    # The inter-token separator also eats `,;` and a closing backtick so a comma/list of §
    # under ONE doc-id resolves EVERY member, not just the first — `04_05 §2.9, §6` and
    # `` `03_05 §3.7`, §3.4 `` were a blind spot (the run stopped at the comma/backtick, so
    # the trailing §-ref rotted unseen). Only separator chars join consecutive § tokens; any
    # word/paren between them ends the run, so a later §X of a DIFFERENT doc is never swept in.
    DOC_SECTION_REF = %r{(\d\d_\d\d)`?\s*((?:§\s*[0-9][\p{L}0-9.]*[\s,;`+/–—-]*)+)}

    # The §-anchor token of a heading = its leading number ("## 🎓 1B. ФОТІУС" → "1b";
    # "### 2.1.3. …" → "2.1.3"; "### Стаття 1: …" → none, letter-led). A single-letter
    # subsection ("### A. …" / "### А. …") under a numbered parent additionally emits a
    # parent-qualified anchor ("## 5." → "### A." ⇒ "5.a"; "## 🧮 4." → "### А." ⇒ "4.а")
    # so a PRECISE `§5.A` / `§4.А` ref resolves to the real subsection, not just its
    # parent (Latin + Cyrillic letters; 03_06 §5.A-D and 02_03 §4.А-Д live this way).
    # Pure.
    def self.heading_anchors(text)
      num_at_level = {} # heading level → its numeric anchor, to parent letter-subsections
      text.lines.grep(/^\#{1,6}\s/).each_with_object([]) do |h, acc|
        level = h[/\A#+/].length
        body  = h.sub(/^#+\s*/, "").sub(/^[^\p{L}\p{N}]+/, "")
        if body =~ /\A([0-9][\p{L}0-9.]*)/
          anchor = Regexp.last_match(1).downcase.sub(/\.+\z/, "")
          acc << anchor
          num_at_level.reject! { |lvl, _| lvl >= level } # same/deeper levels are stale
          num_at_level[level] = anchor
        elsif (m = body.match(/\A(\p{L})\.(?:\s|\z)/)) &&
              (parent = num_at_level.select { |lvl, _| lvl < level }.max_by(&:first)&.last)
          acc << "#{parent}.#{m[1].downcase}"
        end
      end
    end

    def self.file_section_dangling_refs(markdown = File.read(DEFAULT_PATH), docs_dir = DOCS_DIR)
      anchors = Dir.glob(File.join(docs_dir, "*.md")).each_with_object({}) do |f, h|
        id = File.basename(f, ".md")[0, 5]
        h[id] = heading_anchors(File.read(f)) if id =~ /\A\d\d_\d\d/
      end
      markdown.scan(DOC_SECTION_REF).flat_map do |doc, run|
        next [] unless anchors[doc]

        run.scan(/[0-9][\p{L}0-9.]*/).filter_map do |raw|
          next if raw.match?(/\.x\z/) # lowercase ".x" tail = wildcard placeholder

          t = raw.downcase.sub(/\.+\z/, "")
          "`#{doc} §#{raw}`" unless anchors[doc].include?(t) || anchors[doc].any? { |a| a.start_with?("#{t}.") }
        end
      end.uniq
    end

    # --- section↔canon-home guard: One-Home for the tracker itself ---
    # A `#### ` item under a `## §NN` registry section must canon-ref module NN — a
    # `§03/§05` header declares a multi-module set (any OK); a `§NNx` sub-letter
    # heading (§01a/§08b) is one module NN — several may share it (curation split).
    # Catches the drift that once buried §06 deploy items (S*/INF*) under §04 "DevOps"
    # behind apologetic nav-notes. 🔀 cross-cutting / 📌 backlog / 🗄️ archive sections
    # are module-agnostic (section_modules nil/empty) → exempt. (canon-mirror, 00_06 §4)
    def self.section_home_violations(items)
      items.filter_map do |it|
        next if it.section_modules.nil? || it.section_modules.empty?
        next unless it.canon

        mod = it.canon[/\A(\d\d)_/, 1]
        next unless mod

        "#{it.id}: → `#{it.canon}` (module #{mod}) sits under §#{it.section_modules.join('/')}" unless it.section_modules.include?(mod)
      end
    end

    # --- inline residual run-on guard [founder 2026-06-14] ---
    # The item-form standard (00_07 intro) requires open residuals as a VERTICAL list —
    # «≥2 residual'и — завжди список; НЕ паковати кілька `· [ ]` в один рядок». A body line
    # packing ≥2 markdown checkboxes (`· [ ] … · [ ]`) hides residuals from the eye and makes
    # diffs glue-prone. Flags any #### item body line with ≥2 checkboxes; skips the intro
    # blockquote (`> ` example lines), fenced code, and table rows. ANY_ITEM_HEAD spans all
    # sections (the run-on can sit under any #### item). Pure (caller may pass markdown).
    CHECKBOX = /\[[ xX~]\]/
    def self.inline_residual_runon(markdown = File.read(DEFAULT_PATH))
      current = nil
      in_fence = false
      markdown.each_line.with_object([]) do |line, bad|
        in_fence = !in_fence if line.lstrip.start_with?("```")
        next if in_fence
        if (m = line.match(ANY_ITEM_HEAD))
          current = m[1]
          next
        end
        next unless current

        stripped = line.lstrip
        next if stripped.start_with?(">", "|") # intro blockquote example / table row
        bad << "#{current}: #{line.strip[0, 60]}…" if line.scan(CHECKBOX).size >= 2
      end
    end

    # --- verdict-lead guard [DOC-T.19, founder 2026-06-14] ---
    # Universal-Стан: EVERY registry #### item body must LEAD with `- **Стан:**` (verdict /
    # essence + canon pointer) — max homogeneity, no «✅ X»-lead / prose-lead / bare-checkbox
    # (the heterogeneity the founder «can't look at without tears»). Flags any registry item
    # whose first body line after the meta-line (`- **P?** …`) is not `- **Стан:**`. Same
    # registry scope as `parse` (REGISTRY_SECTION, not SKIP). ADVISORY during the §03/§05/§06
    # sweep, flips HARD at 0 (00_06 §3 recipe). Pure.
    STAN_LEAD = /\A-\s+\*\*Стан:\*\*/
    def self.verdict_lead_violations(markdown = File.read(DEFAULT_PATH))
      in_registry = false
      current = nil
      seen_meta = false
      in_fence = false
      markdown.each_line.with_object([]) do |line, bad|
        in_fence = !in_fence if line.lstrip.start_with?("```")
        next if in_fence
        if line.start_with?("## ")
          in_registry = line.match?(REGISTRY_SECTION) && !line.match?(SKIP_SECTION)
          current = nil
          next
        end
        next unless in_registry
        if (m = line.match(ITEM_HEAD))
          current = m[1]
          seen_meta = false
          next
        end
        next unless current

        unless seen_meta
          seen_meta = true if line.match?(/\*\*P[0-3]\*\*/)
          next
        end
        next if line.strip.empty?
        bad << current unless line.lstrip.match?(STAN_LEAD)
        current = nil # check ONLY the first body line per item
      end
    end

    # --- meta-line form guard [DOC-T.23, founder 2026-06-14] ---
    # Every registry #### meta-line is EXACTLY `- **P?** · WHO · STAGE · → канон-реф`:
    # WHO ∈ {🤖, 👤, 🤖+👤} (canonical AI-first combo — rejects 👤+🤖 / 👤/🤖) and NOTHING
    # trails the canon-ref (a `· ✅ ліцензія` / `· 🔗 UNI.1` tail belongs in Стан). The
    # executor parser uses `include?`, so it silently tolerated 👤+🤖 and tails; this locks
    # in the DOC-T.23 standardization. Registry scope as `parse`. (00_06 §3 recipe.)
    META_LINE = /\A-\s+\*\*P[0-3]\*\*\s+·\s+(.+?)\s+·\s+[⚪🟡🟢🔗🌿∅]\s+·\s+(.+?)\s*\z/u
    # ⚖️ joins the meta-line WHO as of DOC-T.33 phase 2 (solo or trailing in a
    # combo — the decider is a 👤-subtype, so it never leads a combo).
    WHO_CANON = [ "🤖", "👤", "⚖️", "🤖+👤", "🤖+⚖️", "👤+⚖️" ].freeze
    def self.meta_form_violations(markdown = File.read(DEFAULT_PATH))
      in_registry = false
      current = nil
      seen_meta = false
      markdown.each_line.with_object([]) do |line, bad|
        if line.start_with?("## ")
          in_registry = line.match?(REGISTRY_SECTION) && !line.match?(SKIP_SECTION)
          current = nil
          next
        end
        next unless in_registry
        if (m = line.match(ITEM_HEAD))
          current = m[1]
          seen_meta = false
          next
        end
        next if current.nil? || seen_meta
        next unless line.match?(/\*\*P[0-3]\*\*/)

        seen_meta = true
        if (mm = line.match(META_LINE))
          who = mm[1].strip
          bad << "#{current}: WHO `#{who}` ∉ {🤖,👤,🤖+👤}" unless WHO_CANON.include?(who)
          bad << "#{current}: meta tail after canon-ref" if mm[2].include?(" · ")
        else
          bad << "#{current}: malformed meta-line"
        end
        current = nil
      end
    end
  end
end
