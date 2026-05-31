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

    Item = Struct.new(:id, :title, :priority, :executors, :canon, keyword_init: true)

    # --- parse markdown → [Item] ---
    def self.parse(markdown)
      items = []
      current = nil
      in_registry = false

      markdown.each_line do |line|
        if line.start_with?("## ")
          items << current if current
          current = nil
          in_registry = line.match?(REGISTRY_SECTION) && !line.match?(SKIP_SECTION)
          next
        end
        next unless in_registry

        if (m = line.match(/^####\s+(?:✅\s+)?([A-Z][A-Za-z0-9]*[.\-][0-9A-Za-z.\-]+)\s+[—-]\s+(.+?)\s*$/))
          items << current if current
          current = Item.new(id: m[1], title: m[2].sub(/\s*✅\s*\z/, ""), executors: [])
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
