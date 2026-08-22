# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [00_07 DRY tooling — #3 item-form contract + drift guards]
#
# Parses the undone-task registry (`## §NN` module sections) of
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
    # `🔀 Cross-cutting` was dropped [DOC-T.71]: it was the only TABLE-shaped registry
    # section, and a table row is invisible to eleven `#### `-keyed guards. Its DOC-T
    # items now live as ordinary `#### ` items in the §-section of their canon module.
    REGISTRY_SECTION = /^## §/
    # Non-actionable / index sections explicitly excluded.
    # ⚠️ `📌` is RETIRED — the tracker has carried no Backlog section for some time
    # (verified 2026-08-10: zero occurrences in the file). The alternative stays in
    # the pattern deliberately, because its cost is nil and its removal would be a
    # silent trap if the section ever returns. What is NOT harmless is the prose:
    # comments elsewhere still read «incl. 📌 Backlog», which invites someone to file
    # an item into a section that does not exist — and `parse` would never see it,
    # which is the invisible-item class this very file guards against. Treat any
    # mention of it as historical.
    SKIP_SECTION = /^## (?:🎯|🚦|📌|🗄️)/

    # WHO axis — who does the OPEN work.
    # ⚖️ = decision-residual (голова, ⊂ 👤 [DOC-T.33]): a verdict that does NOT
    # reduce to a known action — allowed on checkboxes (phase 1) AND in the
    # meta-line WHO (phase 2, scan-on-section).
    EXECUTORS = { "🤖" => :machine, "👤" => :owner, "⚖️" => :decider }.freeze
    # STAGE axis — lifecycle, SEPARATE from WHO [DOC-T.18].
    # 🟡 (in-progress) and 🔗 (blocked) were wrongly mapped as :blocked EXECUTORS —
    # conflating who-with-status (a 🟡 in-progress item is NOT blocked; it routed to
    # the dashboard's "Заблоковано" bucket). Now STAGE is its own axis; "blocked" in
    # the dashboard = STAGE 🔗, not a WHO.
    # ⚫ = vacuous [DOC-T.34]: «нема-що-завершувати» — the premise was refuted /
    # absorbed elsewhere, so there is nothing to activate (≠ 🟢) and nothing to
    # wait on (≠ 🔗); the item stays in place as a closed-canon note. The ⚪↔⚫
    # pair reads "not started" ↔ "nothing to start".
    STAGES = {
      "⚪" => :not_started, "🟡" => :in_progress, "🟢" => :done_inert,
      "🔗" => :blocked, "🌿" => :far_horizon, "⚫" => :vacuous
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
          # only `## §NN` headers carry a module set; anything else → nil (exempt)
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

    # --- table-row ID shape ---
    # An ID may live as a table row (`| DOC-T.12 | … |`) as well as a `#### ` heading,
    # and `all_item_ids` below merges both so a row reusing an active ID is caught.
    # A leading emoji/✅ run is tolerated (`| ✅ OPS.5 |`, `| 🌿 E.59 |`) — the same
    # blind spot that once hid `#### 🌿 UNI.13a`; without it a status-prefixed row
    # was invisible to BOTH the dup tally and inbound-ref resolution.
    # Лідерний emoji/✅-run — єдиний лінійний char-class (НЕ вкладений `(?:[…]+\s*)*`,
    # чий опційний роздільник давав exponential backtracking / ReDoS).
    TABLE_ID_RE = /\A\|[\s✅\p{So}\p{Sk}\u{FE0F}]*\*{0,2}([A-Z][A-Za-z0-9]*[.\-][0-9A-Za-z.\-]+)\*{0,2}\s*\|/

    # --- inbound 00_07 item-ref resolution ---
    # Other docs reference a tracker item as `[`00_07` — <ID>](00_07_…)`. Nothing
    # validated that <ID> is REAL, so `06_02 → 00_07 DOC.5` rotted silently after the
    # item was renamed/removed (the dangling-inbound-ref blind spot the DOC.N namespace
    # work surfaced). `all_item_ids` collects EVERY 00_07 item ID — all #### headings +
    # all table-row first-cells, across ALL sections incl. 📌 Backlog / 🗄️ Архів (NOT
    # section-filtered like parse/table_row_ids, since inbound refs point into those too).
    # `inbound_ref_violations` flags any such ref to a non-existent ID. The em-dash is
    # OPTIONAL (DOC-T.42): the no-dash dialect `[`00_07` DOC.5](00_07_…)` is the same ref
    # and was covered by NOTHING (tracker:check saw only the em-dash form). The captured ID
    # REQUIRES a `.`/`-` separator (`INF.4`, `DOC-T.5`) so a directory-title link
    # (`[`00_07` — Action Plan Tracker](…)`) is NOT a false positive. Pure (caller passes docs_dir).
    ANY_ITEM_HEAD  = /^####\s+(?:[✅\p{So}\p{Sk}\u{FE0F}]+\s+)*([A-Z][A-Za-z0-9]*[.\-][0-9A-Za-z.\-]+)/
    INBOUND_REF_RE = /\[`00_07`\s*(?:[—-]\s*)?([A-Z][A-Za-z0-9]*[.\-][0-9A-Za-z.\-]+)\]\(00_07/

    def self.all_item_ids(markdown)
      markdown.each_line.filter_map { |l| (l.match(ANY_ITEM_HEAD) || l.match(TABLE_ID_RE))&.captures&.first }
    end

    # --- живі ####-тіла як єдине джерело facet-доказів (DOC-T.42 ①) ---
    # Concatenated text of every `#### <ID>` item block (heading → next ####/##).
    # Facet resolution (code_tracker_id_check) must take its verbatim evidence from
    # HERE, not the whole tracker: a retired ID is naturally mentioned by the very
    # §🗄️/DOC-T table-row that documents its retirement, so a whole-file match keeps
    # the dead ID "resolvable" forever — every attempt to write the obituary
    # immunises the phantom (the HW.1-family refs survived 11 passes this way).
    # Ceiling: an obituary written INSIDE a #### body still immunises — form can't
    # see semantics; the table-row necrology is the dominant, now-closed case.
    def self.item_body_text(markdown)
      in_item = false
      markdown.each_line.filter_map do |line|
        in_item = line.match?(ANY_ITEM_HEAD) || (in_item && !line.start_with?("## ", "#### "))
        line if in_item
      end.join
    end

    # --- global ID uniqueness (dup-guard scope widened) ---
    # Every tracker item ID must be unique across the WHOLE file. The earlier tally
    # spanned only the `## §NN` registry sections (parse), so a 📌 Backlog
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
    CHECKBOX_RE = /^\s*[-*]\s*\[[ xX~]\]/
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
    # under ONE doc-id resolves EVERY member, not just the first — `06_07 §1, §3` and
    # `` `03_05 §3.7`, §3.4 `` were a blind spot (the run stopped at the comma/backtick, so
    # the trailing §-ref rotted unseen). Only separator chars join consecutive § tokens; any
    # word/paren between them ends the run, so a later §X of a DIFFERENT doc is never swept in.
    #
    # [DOC-T.60] A §-token is digit-led OR a single-letter LABEL (`A.2`, `B.1.4`, `E.60`).
    # The old token was digit-led only — a ceiling taken to skip *illustrative* `§` mentions,
    # but its real reach was far wider: it silently exempted every doc whose sections are
    # letter-led, and 04_06 is entirely `§A.x`/`§B.x`, so the whole testing canon went
    # unchecked in code AND in `.claude/**` (a planted `04_06 §A.999` returned EXIT 0).
    # The discriminator is NOT the character class — an illustrative `§` is excluded by the
    # `NN_NN` prefix this regex already requires. It is the LABEL SHAPE: one letter + `.` +
    # a digit. That keeps out the genre the ceiling actually meant to skip — prose-shorthand
    # NAMED refs (`05_02 §Модель`, `05_04 §Merkle`, `06_02 §Security`), placeholders
    # (`03_04 §X.Y`, `00_07 §NN`), and non-section IDs (`07_01 §B-02`, `03_05 §FW.2`) — all
    # of which DO carry the NN_NN prefix and stay on the weaker `section_label_drift`
    # ADVISORY by design (00_06 §3). Widening to any letter would sweep in 74 such refs.
    DOC_SECTION_TOKEN = /(?:\p{L}\.)?[0-9][\p{L}0-9.]*/
    DOC_SECTION_REF   = %r{(\d\d_\d\d)`?\s*((?:§\s*#{DOC_SECTION_TOKEN}[\s,;`+/–—-]*)+)}

    # The §-anchor token of a heading = its leading number ("## 🎓 1B. ФОТІУС" → "1b";
    # "### 2.1.3. …" → "2.1.3"; "### Стаття 1: …" → none, word-led) or its leading
    # single-letter LABEL ("## A.4 Assertions" → "a.4"; "### B.1.1 Firmware" → "b.1.1";
    # "### 🔬 E.60 — Merkle …" → "e.60") — DOC-T.60, the ref side alone was not enough:
    # 04_06's headings are letter-led too, so every real `04_06 §A.2` would have read as
    # dangling. Strict superset of the old anchor set (verified across docs/**). A single-letter
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
        if body =~ /\A((?:\p{L}\.)?[0-9][\p{L}0-9.]*)/
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
        # A doc-id with no file at all used to be skipped, on the reasoning that existence
        # is `dangling_refs`'s job. That division was true while this resolver ran only over
        # 00_07 — `dangling_refs` reads `it.canon`, i.e. the META line of a tracker item, and
        # nothing else. Since then the resolver was handed to four consumers, and for the two
        # that matter most (code/`.claude` comments via code_doc_section_refs, prose anywhere)
        # NOTHING answers existence: `external_doc_path` sees only `docs/NN_NN_Name` PATHS,
        # never a bare `NN_NN §X`. So a dissolved doc took its §-refs out of supervision
        # silently. `nil` = no such doc; `[]` = the doc exists and simply has no anchors.
        run.scan(DOC_SECTION_TOKEN).filter_map do |raw|
          next if raw.match?(/\.x\z/) # lowercase ".x" tail = wildcard placeholder — in BOTH
          # branches: the reason it is skipped ("not a section ref, a placeholder") does not
          # depend on whether the target doc still exists.

          next "`#{doc} §#{raw}` — no docs/#{doc}_*.md" unless anchors[doc]

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
    # behind apologetic nav-notes — FIFTEEN of them, surfaced by 00_07's canon-mirror
    # restructuring on 2026-06-01. (That count and date were dropped from the 00_06 §3
    # row on 2026-08-10 and survived only in the commit message; restored here 2026-08-15,
    # because the incident is what BOUGHT this guard and a rule whose evidence lives only
    # in git history is a rule nobody can weigh.) 📌 backlog / 🗄️ archive sections
    # are module-agnostic (section_modules nil/empty) → exempt. (canon-mirror; гейт зареєстровано в 00_06 §3)
    #
    # ⛔ Curation is by THEME — by the subject's unchanging identity — and the obvious
    # alternative was tested and REJECTED (§07, 2026-07-26; moved here from the 00_06 §3
    # row on 2026-08-10, which was its only home). Splitting sub-sections by STATE
    # duplicates the STAGE axis, which already carries state, and would force an item to
    # MIGRATE on every flip. A filing rule that makes items move whenever their state
    # changes is a drift generator, not a filing system — so the rejection is the load-
    # bearing half here, not the mechanic above it.
    def self.section_home_violations(items)
      items.filter_map do |it|
        next if it.section_modules.nil? || it.section_modules.empty?
        next unless it.canon

        mod = it.canon[/\A(\d\d)_/, 1]
        next unless mod

        "#{it.id}: → `#{it.canon}` (module #{mod}) sits under §#{it.section_modules.join('/')}" unless it.section_modules.include?(mod)
      end
    end

    # --- pre-section orphan guard [DOC-T.49] ---
    # `parse` only sees `#### ` items INSIDE a registry section (`## §NN`), so an
    # item sitting ABOVE the first `## ` heading — or under a SKIP section — is invisible to
    # EVERY other tracker gate (dup-ID, meta-form, canon-ref, section-home, verdict-lead all
    # iterate the PARSED set). They then check blind and stay GREEN on a corrupted file — the
    # same false-green shape a glued table row produces. Not hypothetical: an editing accident
    # glued away 00_07's H1 and left DOC-T.48 stranded above every section for a whole commit
    # (225 of 226 items parsed; both doc gates green). Mirror-guard: re-scans with the SAME
    # `####` predicate `parse` uses, so it stays self-consistent with what it protects.
    def self.orphan_item_violations(markdown = File.read(DEFAULT_PATH))
      seen = parse(markdown).map(&:id)
      in_fence = false
      markdown.each_line.with_object([]) do |line, bad|
        in_fence = !in_fence if line.lstrip.start_with?("```")
        next if in_fence
        next unless (m = line.match(ANY_ITEM_HEAD))
        next if seen.include?(m[1])

        bad << "#{m[1]} — `#### ` item outside any `## §NN` registry section → invisible to every tracker gate"
      end
    end

    # --- priority monotonicity within a §-section [DOC-T.73] ---
    # The 00_07 intro states the rule and its own ceiling in one breath: a new item
    # takes the position of its `PN` inside the section's priority cluster, «найгостріше
    # згори (enforcement очима, не лінтером)». The §04 sort of 2026-08-11 measured that
    # ceiling — higher-P items had settled below lower-P ones and nothing went red,
    # because no gate looked at this axis at all.
    #
    # 🔒 CEILING, named here so green never reads as more than it is: this checks the
    # FORM of the order, never its TRUTH. It cannot see whether a `P` is honest (severity
    # vs the item's own body) nor the intro's sibling rule «блокер несе щонайменше `P`
    # того, що блокує» — there the discriminator is the direction of a dependency stated
    # in prose, which is not available to a machine. Both stay on the eye deliberately.
    #
    # The writer already exists (`scripts/tracker_sort.rb`, stable + zero-loss); this is
    # the missing reader. Baseline when built: 8 violations across 5 sections → sorted
    # → 0, and only then wired HARD.
    def self.priority_order_violations(markdown = File.read(DEFAULT_PATH))
      scan_priority_runs(markdown).filter_map do |section, prev_id, prev_p, id, p_num|
        next if p_num >= prev_p

        "#{section}: #{id} (P#{p_num}) стоїть ПІСЛЯ #{prev_id} (P#{prev_p}) — " \
          "вищий пріоритет мусить бути ВИЩЕ в секції (`ruby scripts/tracker_sort.rb`)"
      end
    end

    # Lantern for the check above: «0 violations» means «clean» only if the scan had a
    # non-empty subject. A spec pins this COUNT, so a parser change that silently empties
    # the scope (a renamed section header, a regex that stops matching item heads) turns
    # the gate red instead of green-on-nothing (§Guard-craft: dead scope under a green label).
    def self.priority_ordered_sections(markdown = File.read(DEFAULT_PATH))
      scan_priority_runs(markdown).map(&:first).uniq
    end

    # Yields [section, prev_id, prev_p, id, p_num] for every ADJACENT pair of items
    # inside one `## §` section. Pairs, not items: the rule is about the step between
    # neighbours, and a run resets at every section header.
    def self.scan_priority_runs(markdown)
      section = prev_id = prev_p = cur_id = nil
      in_fence = false

      markdown.each_line.with_object([]) do |line, pairs|
        in_fence = !in_fence if line.lstrip.start_with?("```")
        next if in_fence

        if line.start_with?("## ")
          section = line.start_with?("## §") ? line[/## (§\S+)/, 1] : nil
          prev_id = prev_p = cur_id = nil
          next
        end
        next unless section

        if (m = line.match(ITEM_HEAD))
          cur_id = m[1]
          next
        end
        # Only the meta-line carries `**P?**`; the first hit after a head wins, and
        # `cur_id` is cleared so a `P` quoted later in the body cannot re-trigger.
        next unless cur_id && (pr = line[/\*\*P([0-3])\*\*/, 1])

        p_num = pr.to_i
        pairs << [ section, prev_id, prev_p, cur_id, p_num ] if prev_p
        prev_id = cur_id
        prev_p  = p_num
        cur_id  = nil
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

    # Yields [item_id, first_body_line] for EVERY registry item — the ONE position both
    # lead-rules inspect. Extracted (DOC-T.63) so they cannot drift on WHERE they look:
    # a second copy of this walk would be a second home for "what a Стан-lead is".
    def self.each_item_lead(markdown)
      in_registry = false
      current = nil
      seen_meta = false
      in_fence = false
      markdown.each_line do |line|
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
        yield current, line
        current = nil # check ONLY the first body line per item
      end
    end

    def self.verdict_lead_violations(markdown = File.read(DEFAULT_PATH))
      [].tap do |bad|
        each_item_lead(markdown) { |id, line| bad << id unless line.lstrip.match?(STAN_LEAD) }
      end
    end

    # --- labour-split lead guard [DOC-T.63; founder ban 2026-07-05] ---
    # The Стан-lead must open with the SUBSTANCE (verdict / root / decision), never with the
    # DIVISION OF LABOUR — «Machine-half ✅ SHIPPED» / «Машинна половина ЗАКРИТА» / «вичерпано».
    # WHO on the residual lines and STAGE already say what the machine did and what is left to
    # the human, so the mantra spends the one position that has to carry the most.
    #
    # Why a gate and not the written rule: the ban was ruled AND the corpus swept in one commit
    # (c9ebbe9e, 2026-07-05, which also wrote it into .claude/prompts/deep_archival.md) — and
    # the form returned the SAME day, twice more inside three days, then five times in Ukrainian
    # over the next three weeks. A rule nobody can violate while remembering it is not the
    # problem; a rule that only exists in prose is.
    #
    # NOT DEPRECATED_TERMS (the shape an inventory first prescribed): 00_07 sits in
    # DEPRECATED_EXEMPT, and this ban is POSITIONAL — «machine-half» mid-sentence is legitimate
    # prose and lives in this very file twice.
    # CEILING, stated rather than implied: lead position + a closed token list in BOTH languages.
    # A paraphrase («роботу машини завершено») is invisible BY CONSTRUCTION — the discriminator
    # is FORM, not meaning, and meaning-level judgement measures ~2% precision in this corpus
    # (00_06 §3 design rule). Widening it into semantics would buy noise, and a noisy gate is off.
    LEAD_ORNAMENT = /\A[\s*_~`✅🟢🔵⚪🤖👤·—–-]+/
    LABOUR_SPLIT_TOKEN = /\A(?:machine[-\s]?half|машинн\p{L}*\s+(?:половин|частин)\p{L}*|вичерпан\p{L}*)/i
    def self.labour_split_lead(markdown = File.read(DEFAULT_PATH))
      [].tap do |bad|
        each_item_lead(markdown) do |id, line|
          rest = line.lstrip.sub(STAN_LEAD, "").sub(LEAD_ORNAMENT, "")
          bad << "#{id}: #{rest.strip[0, 48]}…" if rest.match?(LABOUR_SPLIT_TOKEN)
        end
      end
    end

    # --- stale WHO guard — meta OVERSTATES its open work ---
    # [DOC-T.52 2026-07-26 (🤖 only) · DOC-T.55 2026-08-05 (all three glyphs + empty set)]
    # The item-form standard (00_07 intro) defines the meta-line WHO as the UNION of
    # every OPEN residual's WHO — «закрита половина туди не входить». So once an
    # item's half ships, that glyph must LEAVE its meta-line. It silently doesn't:
    # `meta_form_violations` validates only the WHO token's SHAPE, never whether it
    # still matches the open checkboxes, so a shipped half keeps advertising
    # free work that no longer exists — the second-commonest tracker drift after
    # STAGE 🟡→🟢, and the one that makes a "what's doable now" scan lie.
    #
    # 🔴 The first cut guarded ONE glyph of a three-member enum and exited on the EMPTY
    # SET — two holes its green runs could never show (DOC-T.55). Both are the same
    # disease as the sibling's: a check that covers one member of an enum reads, from its
    # name and its green run, exactly like one that covers all of them; and a gate whose
    # subject can be empty is green forever. So the guard now ranges over all three
    # executors AND over items with nothing open at all.
    #
    # ⚠️ Coverage is ASYMMETRIC because `⚖️ ⊂ 👤` (00_07 §розмітка), exactly as
    # `understated_who` reads it in the mirror direction: a meta `👤` is backed by an open
    # `👤` OR `⚖️`, while a meta `⚖️` needs an open `⚖️` — the subset runs one way. Measured
    # on the live corpus: dropping the subset rule turns 4 honest items (HW.36 · E.59 ·
    # UI.1 · INF.22) into false positives, i.e. the naive symmetrization is WRONG, not
    # merely noisy.
    #
    # Two exemptions hold false positives at zero (both empirically derived — each was a
    # real hit that turned out honest). Note they are **item-wide by construction, not by
    # oversight**: an UNDETERMINED executor can back ANY meta glyph, so it cannot be
    # narrowed per-glyph.
    #   • a 🔗-led residual — delegated/gated into another item, whose eventual WHO
    #     lives THERE, so the meta glyph is an honest forward-claim (BIZ.14);
    #   • a residual carrying NO explicit WHO glyph (e.g. a 🌿-led far-horizon line)
    #     — WHO is simply undeclared, so "that half is done" does not follow
    #     (ARCH.18 / E.31 — both genuinely machine work, just far-horizon).
    # 🔴 CEILING, measured 2026-08-05 and materially WIDER after the three-glyph flip:
    # these exemptions silence 27 of 29 literal hits (they silenced far fewer while the
    # guard read one glyph). That is the honest price of "undetermined backs anything" —
    # but it means a green run here is evidence about items whose residuals ALL declare an
    # executor, and about nothing else. Narrowing it needs a canon decision on what a
    # 🔗/🌿 residual may forward-claim, not a code change.
    # Pure (caller may pass markdown).
    # `\Z` (not `\z`) — each_line keeps the trailing "\n", which `\z` never matches.
    OPEN_RESIDUAL = /\A-\s+\[ \]\s*(.+)\Z/
    WHO_GLYPH     = /[🤖👤⚖]/
    # LEADING WHO run of a residual body — one glyph or a `+`-joined combo. Both WHO gates
    # anchor here instead of scanning the whole line: a 👤 residual may CITE closed machine
    # work in prose ("§5.3 вже 🤖-verified"), and counting that as an open 🤖 blinds both
    # directions at once (proven on HW.9, 2026-07-26). [DOC-T.54]
    # 🔴 CEILING both WHO gates share: the executor is read ONLY from the leading token, so a
    # residual with a DECORATIVE lead (`- [ ] ✨ 🤖 …`, `- [ ] 🧹 🤖 …`) is invisible to both —
    # `understated_who` will not flag its machine work, and `stale_who` can FALSELY flag
    # the item as advertising 🤖 nobody backs. Widening the anchor to skip a non-WHO prefix would
    # reopen the prose-mention hole this replaced, so the ceiling is declared, not papered over.
    WHO_LEAD      = /\A(?:🤖|👤|⚖️)(?:\+(?:🤖|👤|⚖️))*/
    EXECUTOR_GLYPHS = %w[🤖 👤 ⚖].freeze
    # STAGEs under which a non-empty meta-WHO over ZERO open residuals is HONEST — the
    # WHO names a future executor rather than the union of open work. Both are read off
    # the 00_07 §розмітка legend, and both are what the corpus actually carries:
    #   🌿 far-horizon — the work is past the horizon, so it has no checkbox yet;
    #   ⚫ vacuous — «нема-що-завершувати», the item stays in place as a closed-canon note.
    # Deliberately NOT here: 🔗. A blocked item's trigger must be NAMED (legend: «🔗 без
    # названої події = прихований ⚪»), so a 🔗 with nothing open is itself suspect. No
    # corpus case exists for it either — inventing the exemption would be a rule from the
    # head, and both existing exemptions were derived from real honest hits instead.
    FORWARD_WHO_STAGES = %w[🌿 ⚫].freeze

    def self.stale_who(markdown = File.read(DEFAULT_PATH))
      in_registry = false
      in_fence = false
      current = nil
      items = []

      markdown.each_line do |line|
        in_fence = !in_fence if line.lstrip.start_with?("```")
        next if in_fence || line.lstrip.start_with?(">") # intro blockquote examples

        if line.start_with?("## ")
          in_registry = line.match?(REGISTRY_SECTION) && !line.match?(SKIP_SECTION)
          current = nil
          next
        end
        next unless in_registry

        if (m = line.match(ITEM_HEAD))
          current = { id: m[1], who: nil, stage: nil, seen_meta: false, open: [] }
          items << current
          next
        end
        next unless current

        if !current[:seen_meta] && line.match?(/\*\*P[0-3]\*\*/)
          current[:seen_meta] = true
          # WHO / STAGE are the 2nd / 3rd `·`-separated meta segments (shape HARD-enforced)
          current[:who]   = line.split("·")[1].to_s
          current[:stage] = line.split("·")[2].to_s
        elsif (r = line.match(OPEN_RESIDUAL))
          current[:open] << r[1]
        end
      end

      items.filter_map do |it|
        next unless it[:who]

        # ZERO open residuals: the union is EMPTY, so any WHO overstates it. The standard
        # has no empty WHO token (`WHO_CANON`), so the honest resolutions are «finished →
        # §🗄️ Архів» or «the open work is missing — write the residual», never a blank axis.
        if it[:open].empty?
          next if FORWARD_WHO_STAGES.any? { |g| it[:stage].include?(g) }
          next "#{it[:id]}: meta WHO «#{it[:who].strip}» over ZERO open residuals " \
               "(done → §🗄️, or the open work is unwritten)"
        end

        # An UNDETERMINED executor backs any glyph → item-wide exemption (see ceiling above).
        next if it[:open].any? { |b| b.lstrip.start_with?("🔗") || !b.match?(WHO_GLYPH) }

        # LEADING token, never `include?` over the line: a 👤 residual that CITES closed
        # machine work ("§5.3 вже 🤖-verified") would otherwise read as an open 🤖 and
        # keep this gate silent about a meta 🤖 nobody backs — proven on HW.9, where it
        # masked exactly that drift being introduced. Mirrors `understated_who`. [DOC-T.54]
        leads = it[:open].map { |b| b[WHO_LEAD].to_s }
        stale = EXECUTOR_GLYPHS.select do |g|
          it[:who].include?(g) &&
            leads.none? { |lead| lead.include?(g) || (g == "👤" && lead.include?("⚖")) }
        end
        next if stale.empty?

        "#{it[:id]}: meta WHO «#{it[:who].strip}» claims #{stale.join(' ')} — no open residual backs it"
      end
    end

    # --- meta-WHO understates its own open work [DOC-T.54 — reverse axis of DOC-T.52] ---
    # `stale_who` enforces ONE direction of a contract its own comment states as
    # a UNION ("meta-line WHO must stay the UNION of OPEN residuals"): it catches meta
    # OVERSTATING (claims an executor nobody backs) and is structurally blind to meta
    # UNDERSTATING — an open 🤖 residual the meta-line never mentions. That direction is
    # the costlier one: the meta-line IS the scan layer, so a pure-👤 meta reads as
    # "nothing here for the machine" while the body holds machine work (HW.1 — a P0
    # critical-path item — hid SIX open 🤖 residuals this way; 17 items corpus-wide, 7 of them
    # in §01a — measured with THIS version against the pre-fix tracker, since the first cut's
    # own tally was suppressed by its own two bugs).
    # Same two exemptions as the sibling: 🔗-led (delegated — eventual WHO lives in the
    # gating item) and glyph-less (🌿-led — WHO simply undeclared).
    # ⚖️ ⊂ 👤 (00_07 §розмітка), so a meta 👤 legitimately covers an open ⚖️ residual;
    # the reverse is not true — 👤 work is not covered by a meta ⚖️. That subset relation
    # is also why an item spanning all THREE executors needs NO exemption: {🤖,👤,⚖️}
    # collapses onto the legal pair `🤖+👤`, so "union of open" is always satisfiable in
    # two slots. (A first cut exempted `kinds.size > 2` on a "physically unsatisfiable"
    # premise its own ⚖️⊂👤 line refuted — the exemption silenced the gate on ~12% of the
    # corpus, including three items carrying the exact pure-👤-over-machine-work pathology
    # this guard exists to catch. Adversarial review, 2026-07-26.)
    # 🔴 Executors are read from the residual's LEADING token, never `include?` over the
    # whole line: a 👤 checkbox may MENTION 🤖 in prose ("§5.3 вже 🤖-verified") — that is
    # closed work being cited, not open machine work, and counting it makes the meta-line
    # advertise 🤖 nobody backs, i.e. manufactures the very DOC-T.52 drift this guards.
    # Pure (caller may pass markdown). Returns human-readable violation strings.
    # `EXECUTOR_GLYPHS` is shared with the sibling above (one home) — note it spells ⚖
    # WITHOUT the FE0F variation selector, which the `g == "👤"` / `g == "⚖"` comparisons
    # in both guards depend on; swapping it for `EXECUTORS.keys` silently breaks ⚖️ ⊂ 👤.

    def self.understated_who(markdown = File.read(DEFAULT_PATH))
      in_registry = false
      in_fence = false
      current = nil
      items = []

      markdown.each_line do |line|
        in_fence = !in_fence if line.lstrip.start_with?("```")
        next if in_fence || line.lstrip.start_with?(">") # intro blockquote examples

        if line.start_with?("## ")
          in_registry = line.match?(REGISTRY_SECTION) && !line.match?(SKIP_SECTION)
          current = nil
          next
        end
        next unless in_registry

        if (m = line.match(ITEM_HEAD))
          current = { id: m[1], who: nil, seen_meta: false, open: [] }
          items << current
          next
        end
        next unless current

        if !current[:seen_meta] && line.match?(/\*\*P[0-3]\*\*/)
          current[:seen_meta] = true
          current[:who] = line.split("·")[1].to_s
        elsif (r = line.match(OPEN_RESIDUAL))
          current[:open] << r[1]
        end
      end

      items.filter_map do |it|
        next unless it[:who]

        # 🔗-led residuals delegate their WHO to the gating item — same exemption the
        # overstate axis makes, and for the same reason.
        live = it[:open].filter_map { |b| b[WHO_LEAD] }
        kinds = EXECUTOR_GLYPHS.select { |g| live.any? { |lead| lead.include?(g) } }

        missing = kinds.reject do |g|
          it[:who].include?(g) || (g == "⚖" && it[:who].include?("👤"))
        end
        next if missing.empty?

        counts = missing.map { |g| "#{g}×#{live.count { |b| b.include?(g) }}" }.join(" ")
        "#{it[:id]}: meta WHO «#{it[:who].strip}» misses #{counts} (open residuals it never declares)"
      end
    end

    # --- bench-session tag symmetry [DOC-T.34 ①] ---
    # Bench work is organized in NAMED SESSIONS (one coherent stand-day block);
    # the session registry is SSOT in firmware/scripts/bench/RUNBOOK.md §6
    # (`| [bench:slug] | sections | IDs |` rows — the tag itself anchors the row,
    # so the RUNBOOK's other tables can't false-match), and a 00_07 item whose
    # bench work belongs to session X carries a `[bench:X]` tag on the checkbox.
    # Two-way symmetry: a tag must name a registered session AND its item must be
    # in that session's row; every ID a row lists must carry the tag. Closes the
    # FW.8↔FW.20-style cross-ref asymmetry and makes a bench day grep-plannable.
    BENCH_TAG    = /\[bench:([a-z0-9-]+)\]/
    BENCH_ROW    = /\A\|\s*\[bench:([a-z0-9-]+)\]\s*\|[^|]*\|([^|]*)\|/
    RUNBOOK_PATH = File.expand_path("../../firmware/scripts/bench/RUNBOOK.md", __dir__)

    def self.bench_sessions(runbook)
      runbook.each_line.with_object({}) do |line, h|
        next unless (m = line.match(BENCH_ROW))

        # expand_prose_ids so a slash-family shorthand (`FW.8/20`) in a registry
        # row names BOTH members — a raw scan would demand a literal "FW.8/20"
        # tag and silently unsee the real FW.20 (the very asymmetry this guards)
        h[m[1]] = expand_prose_ids(m[2])
      end
    end

    # Tags are read ONLY from checkbox rows (the documented home — 00_07 §розмітка)
    # and never from fenced code: a grep-example ```[bench:x]``` inside an item body
    # must not satisfy the "item carries the tag" leg (proven false-green in review).
    def self.bench_item_tags(markdown)
      current = nil
      in_fence = false
      markdown.each_line.with_object(Hash.new { |h, k| h[k] = [] }) do |line, h|
        in_fence = !in_fence if line.lstrip.start_with?("```")
        next if in_fence
        # a `## ` header ends the previous item's body — without this, a tag
        # mentioned in an archive table row leaks onto the last #### item
        current = nil if line.start_with?("## ")
        current = line[ANY_ITEM_HEAD, 1] || current
        next unless current && line.match?(CHECKBOX_RE)

        line.scan(BENCH_TAG) { |slug,| h[current] << slug }
      end
    end

    def self.bench_tag_violations(markdown = File.read(DEFAULT_PATH),
                                  runbook = (File.read(RUNBOOK_PATH) if File.exist?(RUNBOOK_PATH)))
      tags = bench_item_tags(markdown)
      # a vanished registry must not crash the whole tracker:check, but with live
      # tags in 00_07 it can't silently pass either — one honest violation instead
      return tags.empty? ? [] : [ "RUNBOOK §6 registry not found (#{RUNBOOK_PATH}) — bench-tag symmetry unverifiable" ] if runbook.nil?

      sessions = bench_sessions(runbook)
      bad = []
      tags.each do |id, slugs|
        slugs.uniq.each do |slug|
          if sessions.key?(slug)
            bad << "#{id}: [bench:#{slug}] — item not in that session's RUNBOOK §6 row" unless sessions[slug].include?(id)
          else
            bad << "#{id}: [bench:#{slug}] — no such session in RUNBOOK §6"
          end
        end
      end
      sessions.each do |slug, ids|
        ids.each do |id|
          bad << "RUNBOOK §6 [bench:#{slug}]: #{id} carries no tag in 00_07" unless tags[id].include?(slug)
        end
      end
      bad
    end

    # --- дім-кластер marker guard [DOC-T.34 ③] ---
    # A coordination cluster (координатор ⊃ важелі — DRY without an item-merge)
    # is declared on ITEM HEADINGS as `[кластер:slug:дім]` / `[кластер:slug:важіль]`,
    # formalizing the ad-hoc «[дім X кластера]» / «[candidate-важіль Y]» spellings
    # into ONE greppable, symmetric form. Every slug needs exactly ONE дім and
    # ≥1 важіль (a дім alone / a важіль pointing at no дім is a half-migrated
    # cluster); a malformed [кластер:…] tail is flagged. Distinct from the
    # `[поглинув X]` mirror-pair spelling — that one stays free prose.
    CLUSTER_MARKER = /\[кластер:([a-z0-9-]+):(дім|важіль)\]/
    CLUSTER_ANY    = /\[кластер:[^\]]*\]/

    def self.cluster_marker_violations(markdown = File.read(DEFAULT_PATH))
      bad = []
      in_fence = false
      clusters = Hash.new { |h, k| h[k] = { "дім" => [], "важіль" => [] } }
      markdown.each_line do |line|
        in_fence = !in_fence if line.lstrip.start_with?("```")
        next if in_fence
        next unless (m = line.match(ANY_ITEM_HEAD))

        line.scan(CLUSTER_ANY) do |raw|
          if (mm = raw.match(CLUSTER_MARKER))
            clusters[mm[1]][mm[2]] << m[1]
          else
            bad << "#{m[1]}: malformed #{raw} (want [кластер:slug:дім|важіль])"
          end
        end
      end
      clusters.each do |slug, roles|
        bad << "кластер:#{slug}: #{roles['дім'].size} дім-markers (need exactly 1)" if roles["дім"].size != 1
        bad << "кластер:#{slug}: no важіль items (дім alone)" if roles["важіль"].empty?
      end
      bad
    end

    # --- meta-line form guard [DOC-T.23, founder 2026-06-14] ---
    # Every registry #### meta-line is EXACTLY `- **P?** · WHO · STAGE · → канон-реф`:
    # WHO ∈ {🤖, 👤, 🤖+👤} (canonical AI-first combo — rejects 👤+🤖 / 👤/🤖) and NOTHING
    # trails the canon-ref (a `· ✅ ліцензія` / `· 🔗 UNI.16` tail belongs in Стан). The
    # executor parser uses `include?`, so it silently tolerated 👤+🤖 and tails; this locks
    # in the DOC-T.23 standardization. Registry scope as `parse`. (00_06 §3 recipe.)
    META_LINE = /\A-\s+\*\*P[0-3]\*\*\s+·\s+(.+?)\s+·\s+[⚪🟡🟢🔗🌿⚫]\s+·\s+(.+?)\s*\z/u
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
          bad << "#{current}: WHO `#{who}` ∉ {#{WHO_CANON.join(',')}}" unless WHO_CANON.include?(who)
          bad << "#{current}: meta tail after canon-ref" if mm[2].include?(" · ")
        else
          bad << "#{current}: malformed meta-line"
        end
        current = nil
      end
    end
  end
end
