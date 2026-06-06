# frozen_string_literal: true

# [00_07 DRY tooling — #1 auto-dashboard + #3 format contract]
#
# Parses the undone-task registry (§-module + 🔀 cross-cutting sections) of
# docs/00_07_Action_Plan_Tracker.md and regenerates the 🚦 Dashboard between the
# AUTO markers, so the executor-grouped index can never drift from the registry
# — the "one fact, one place" principle made mechanical (user, 2026-05-29).
#
# Pure Ruby (no Rails) — runnable from a rake task or CI without booting the app.
module Tracker
  class Dashboard
    DEFAULT_PATH = File.expand_path("../../docs/00_07_Action_Plan_Tracker.md", __dir__)
    DOCS_DIR = File.expand_path("../../docs", __dir__)
    START_MARK = "<!-- DASHBOARD:AUTO:START -->"
    END_MARK   = "<!-- DASHBOARD:AUTO:END -->"

    # #### items under these sections feed the dashboard (mirror canon modules).
    REGISTRY_SECTION = /^## (?:§|🔀)/
    # Non-actionable / index sections explicitly excluded.
    SKIP_SECTION = /^## (?:🎯|🚦|📌|🗄️)/

    EXECUTORS = { "🤖" => :machine, "👤" => :owner, "🔗" => :blocked, "🟡" => :blocked }.freeze
    PRIORITY_RANK = { "P0" => 0, "P1" => 1, "P2" => 2, "P3" => 3 }.freeze
    HEADINGS = {
      machine: "🤖 Machine-doable (AI, non-gated)",
      owner: "👤 На тобі (власник)",
      blocked: "🔗 Заблоковано (чекає іншого)"
    }.freeze

    Item = Struct.new(:id, :title, :priority, :executors, :canon, :section_modules, keyword_init: true)

    # `## §NN`-section module set: `§01–§02`→["01","02"], `§03/§05`→["03","05"].
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
            # the meta-line `- **P?** · 👤/🤖/🔗 · → canon` carries the executor(s)
            EXECUTORS.each { |emoji, role| current.executors << role if line.include?(emoji) }
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

    # --- registry table-row IDs (dup-guard blind-spot fix, 2026-06-01) ---
    # The dup-guard tallies #### heading IDs only; an ID used as BOTH a table-row
    # (e.g. `| DOC-T.12 | … |` in the DOC-drift registry) AND a #### heading slipped
    # through silently (the DOC-T.12 ↔ DOC-T.13 collision). This returns the first-cell
    # ID token of every table row inside the §/🔀 registry sections so the caller
    # can merge them into the dup tally. Same ID shape as `parse`; header/separator
    # rows (no ID in the first cell) and **bold** wrappers are handled.
    # A leading emoji/✅ run is tolerated (`| ✅ OPS.5 |`, `| 🌿 E.59 |`) — the same
    # blind spot that once hid `#### 🌿 UNI.13a`; without it a status-prefixed backlog
    # row was invisible to BOTH the dup tally and inbound-ref resolution (2026-06-03).
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

    # --- inbound 00_07 item-ref resolution (2026-06-03) ---
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

    # --- global ID uniqueness (dup-guard scope widened 2026-06-03) ---
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

    # --- prose ID-list refs after a 00_07 link (2026-06-03) ---
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

    # --- CHEM.N in-silico chemistry-note refs (2026-06-06) ---
    # The HW.5.IS in-silico chemistry backlog is a bulleted, triaged list (not #### items),
    # so its 31 notes carry their own CHEM.N IDs (`- [ ] **CHEM.6** — …`), standardized from
    # the old ad-hoc `note N` so the refs are guardable like every other 00_07 ID (founder
    # 2026-06-06: `note N` was unanchored + already restated across 01_03/SUMMARY/L1/scripts →
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

    # Scanned for CHEM.N refs: the canon docs (incl. the in_silico protocol subdir) AND the
    # in_silico scripts (founder: the refs leaked into CODE too). 00_07 is the definer → skipped.
    CHEM_SCAN_GLOBS = ["docs/**/*.md", "tools/in_silico/scripts/*.py"].freeze

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

    # --- render 🚦 Dashboard markdown (focus: P0/P1; P2 as a tail count) ---
    def self.render(items)
      open = open_items(items)
      out = []
      HEADINGS.each do |role, heading|
        in_role = open.select { |it| it.executors.include?(role) }
        low = %w[P2 P3]
        focus = in_role.reject { |it| low.include?(it.priority) }
                       .sort_by { |it| [ PRIORITY_RANK[it.priority] || 9, it.id ] }
        lown = in_role.count { |it| low.include?(it.priority) }
        out << "### #{heading}"
        if focus.empty?
          out << "_(жодного відкритого P0/P1#{lown.positive? ? "; #{lown} × P2/P3 — див. §модулі" : ''})_"
        else
          focus.each do |it|
            pr  = it.priority ? " **#{it.priority}**" : ""
            ref = it.canon ? " → `#{it.canon}`" : ""
            out << "- `#{it.id}`#{pr} — #{it.title}#{ref}"
          end
          out << "_(+ #{lown} × P2/P3 — див. §модулі)_" if lown.positive?
        end
        out << ""
      end
      out.join("\n").rstrip
    end

    # --- #3 conformance: open items missing priority / canon-ref ---
    def self.issues(items)
      items.filter_map do |it|
        missing = []
        missing << "priority" unless it.priority
        missing << "executor" if it.executors.empty?
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

    # --- section↔canon-home guard: One-Home for the tracker itself ---
    # A `#### ` item under a `## §NN` registry section must canon-ref module NN — a
    # `§03/§05` or `§01–§02` header declares a multi-module set, any of which is OK.
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

    # --- regenerate the AUTO block in place ---
    def self.regenerate(path = DEFAULT_PATH)
      md = File.read(path)
      raise "AUTO markers not found in #{path}" unless md.include?(START_MARK) && md.include?(END_MARK)

      block = "#{START_MARK}\n#{render(parse(md))}\n#{END_MARK}"
      File.write(path, md.sub(/#{Regexp.escape(START_MARK)}.*?#{Regexp.escape(END_MARK)}/m, block))
    end

    # --- CI drift-guard + conformance report ---
    def self.check(path = DEFAULT_PATH)
      md = File.read(path)
      items = parse(md)
      current = md[/#{Regexp.escape(START_MARK)}\n(.*?)\n#{Regexp.escape(END_MARK)}/m, 1]
      { drift: current&.strip != render(items).strip, issues: issues(items), open: open_items(items).size }
    end
  end
end
