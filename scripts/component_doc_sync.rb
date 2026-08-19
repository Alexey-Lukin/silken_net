#!/usr/bin/env ruby
# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Doc↔code sync gate for the COMPONENT registry in 04_04 [UI.12].
#
# Sibling of scripts/model_doc_sync.rb, which holds 04_01 ⟷ app/models/ and
# 04_02 ⟷ app/services|workers. The component surface was the last registry in
# this repo with no gate at all: 04_04 §6 is hand-maintained prose, so a
# component shipped without a row — or a row outliving its file — stayed green
# forever. Both had already happened when this was written.
#
# Enforces:
#
#   1. app/views/components/**        ⟷ §6.4 rows                       (1:1)
#   2. app/views/shared/{ui,iot,web3} ⟷ §6.1 / §6.2 / §6.3 rows          (1:1)
#   3. app/views/components/*/ dirs   ⟷ namespaces drawn in the §1 tree  (1:1)
#
# ── WHY THE PARSER IS THE HARD PART (this gate's founding defect) ───────────
#
# The registry writes a component in THREE different row forms, and a parser
# that knows only one reports a drift that does not exist. Measured while
# building this: reading form A alone said "35 components undocumented";
# teaching it form B dropped that to 5; form C moved a THIRD surface again.
# The tracker item that ordered this gate carried the first number as fact.
#
#   A  detailed   | `Ns::Class` | `ns/class.rb` | props | description |
#   B  compressed | `Ns`        | `A`, `B`, `C` | props |
#                   (§6.4 "Інші Доменні Компоненти" — one row per NAMESPACE)
#   C  shared     | **Name**    | `name.rb`     | props | description |
#                   (§6.1–6.3 — bold, not a code span, and no namespace)
#
# So a FOURTH row form must be taught to `registry_entries` here, or this gate
# turns an honest addition red. That is the ceiling, and it is why the spec
# pins one example of every form (spec/lib/component_doc_sync_spec.rb).
#
# ── NAMED CEILINGS (what this gate does NOT see) ────────────────────────────
#
#   · It compares CLASS NAMES only — never props, never the prose beside them.
#     A row whose `Props` column is stale passes. Cite this gate only for the
#     class it actually catches.
#   · §1's tree is checked at NAMESPACE granularity, not leaf, and that is a
#     decision rather than a shortcut: the tree used to enumerate leaves too,
#     which made it a SECOND registry that rotted faster than the first. Leaf
#     truth has exactly one home — §6. Re-adding leaves there without also
#     gating them re-opens this hole.
#   · shared/ registries are matched on the BASENAME (`StatusBadge`), because
#     that is what §6.1–6.3 write; the real classes are `Views::Shared::UI::*`.
#
# Pure Ruby (no Rails / no bundle). Run: ruby scripts/component_doc_sync.rb
# Exit 0 = in sync; exit 1 = drift (lists the divergence). Method/why → 00_06 §3.

require "set"

module ComponentDocSync
  DOC_REL        = "docs/04_04_Phlex_UI_and_Tailwind.md"
  COMPONENTS_REL = "app/views/components"
  SHARED_REL     = "app/views/shared"

  # `application_component.rb` is the Phlex BASE class, documented in 04_04 §2 —
  # not a domain component, so §6.4 must not list it. Mirrors model_doc_sync's
  # NON_MODEL_BASENAMES exemption for application_record.rb.
  NON_COMPONENT_BASENAMES = %w[application_component.rb].freeze

  # shared subdir → [its section, the section that follows it]
  SHARED_SECTIONS = { "ui" => %w[6.1 6.2], "iot" => %w[6.2 6.3], "web3" => %w[6.3 6.4] }.freeze

  # 🔴 [UI.3] FOURTH axis: the Lookbook preview table in §10. It was the only
  # registry in this document with NO guard at all, and it had drifted — a row for
  # `AlertBadgePreview` survived the deletion of both the component AND its preview
  # (2026-07-27), while §8.3 of the SAME page records that deletion explicitly. So
  # the page asserted a preview exists and that it was removed, seventy lines apart,
  # both green. Previews live OUTSIDE `app/views` (`spec/components/previews`), which
  # is exactly why the existing three axes could not see them.
  PREVIEWS_REL = "spec/components/previews"

  module_function

  def camelize(snake) = snake.split("_").map(&:capitalize).join

  # Рядки таблиці превʼю СТРОГО між заголовком §10 і наступним `## `.
  # ⚠️ Патерн допускає ЦИФРУ в імені (`Web3AddressPreview`) — читач із `[A-Za-z]+`
  # мовчки губить той рядок і звітує його як відсутній у доці.
  def registry_previews(lines)
    from = heading_index(lines, "## 10. ")
    to   = lines[(from + 1)..].index { |l| l.start_with?("## ") }
    to = to.nil? ? lines.size : from + 1 + to
    lines[from...to].filter_map { |l| l[/\A\|\s*`([A-Z][A-Za-z0-9]*Preview)`/, 1] }.to_set
  end

  # Index of the first line starting with `prefix`; raises rather than silently
  # scanning an empty range — a gate over an empty set is green forever.
  def heading_index(lines, prefix)
    lines.index { |l| l.start_with?(prefix) } or
      raise ArgumentError, "component_doc_sync: no line starting with #{prefix.inspect} in #{DOC_REL}"
  end

  # Every component named by table rows between two line indices, in any of the
  # three row forms the registry actually uses (see the header).
  #
  #   qualified: true  → form B expands to "Ns::Leaf" (the §6.4 convention)
  #   qualified: false → form C yields the bare basename (§6.1–6.3 convention)
  def registry_entries(lines, from_idx, to_idx, qualified:)
    names = []

    lines[from_idx...to_idx].each do |line|
      next unless line.start_with?("|")

      first = line.split("|").map(&:strip)[1].to_s

      # Anchored on a CamelCase lead on purpose: §6.1's own range also carries the
      # StatusBadge state-map (`pending`, `dormant`, …) and the Skeleton variant
      # table (`:balance`, `:card`, …), whose first cells are code spans too. A
      # laxer `[A-Za-z0-9:]+` reads those as components — the neighbouring-domain
      # -of-one-token trap. Every real entry is a Ruby constant, so it starts uppercase.
      if (bold = first[/\A\*\*([A-Z][A-Za-z0-9]*)\*\*\z/, 1])       # form C
        names << bold
      elsif (span = first[/\A`([A-Z][A-Za-z0-9:]*)`\z/, 1])
        if span.include?("::")                                      # form A
          names << span
        elsif qualified                                             # form B
          line.split("|").map(&:strip)[2].to_s
              .scan(/`([A-Za-z0-9]+)`/) { names << "#{span}::#{Regexp.last_match(1)}" }
        end
      end
    end

    names.to_set
  end

  # Class names of every .rb under `dir`. `nested` keeps the directory segments
  # (Ns::Leaf); otherwise only the basename.
  def code_classes(dir, nested:, reject: [])
    Dir.glob(File.join(dir, "**/*.rb")).sort.filter_map do |path|
      rel = path.delete_prefix(dir + "/")
      next if reject.include?(rel)

      segments = rel.sub(/\.rb\z/, "").split("/")
      (nested ? segments : [ segments.last ]).map { |s| camelize(s) }.join("::")
    end.to_set
  end

  # Namespaces drawn under the `app/views/components/` node of the §1 ASCII tree.
  def tree_namespaces(lines)
    body = lines[heading_index(lines, "### Ієрархія Компонентів")...heading_index(lines, "### Потік Рендерингу")]

    node = body.index { |l| l.include?("#{COMPONENTS_REL}/") } or
      raise ArgumentError, "component_doc_sync: no #{COMPONENTS_REL}/ node in the #{DOC_REL} §1 tree"

    body[(node + 1)..].take_while { |l| l.strip != "```" }
                      .filter_map { |l| l[%r{[├└]──\s+(\w+)/}, 1] }
                      .to_set
  end

  def compare(label, code, doc, code_home, doc_home)
    (code - doc).sort.map { |n| "#{label}: `#{n}` exists in #{code_home} but is NOT in #{doc_home}" } +
      (doc - code).sort.map { |n| "#{label}: `#{n}` is in #{doc_home} but has NO file in #{code_home}" }
  end

  # The whole audit as a pure function of a repo root. Returns violation strings.
  def audit(root)
    doc_lines      = File.readlines(File.join(root, DOC_REL), chomp: true)
    components_dir = File.join(root, COMPONENTS_REL)
    errors         = []

    domain_code = code_classes(components_dir, nested: true, reject: NON_COMPONENT_BASENAMES)
    domain_doc  = registry_entries(doc_lines, heading_index(doc_lines, "### 6.4 "),
                                   heading_index(doc_lines, "### 6.5 "), qualified: true)
    errors += compare("domain component", domain_code, domain_doc,
                      "#{COMPONENTS_REL}/", "04_04 §6.4")

    SHARED_SECTIONS.each do |subdir, (section, next_section)|
      shared_code = code_classes(File.join(root, SHARED_REL, subdir), nested: false)
      shared_doc  = registry_entries(doc_lines, heading_index(doc_lines, "### #{section} "),
                                     heading_index(doc_lines, "### #{next_section} "), qualified: false)
      errors += compare("shared/#{subdir}", shared_code, shared_doc,
                        "#{SHARED_REL}/#{subdir}/", "04_04 §#{section}")
    end

    # Preview classes on disk ⟷ §10 table rows, 1:1. Names carry a digit
    # (`Web3AddressPreview`), so the pattern must allow one — a `[A-Za-z]+`-only
    # reader silently drops that row and then reports it as missing from the doc.
    preview_code = Dir.glob(File.join(root, PREVIEWS_REL, "*_preview.rb"))
                      .map { |f| camelize(File.basename(f, ".rb")) }.to_set
    # 🔴 ЯКІР, як у трьох інших осей. Доти ця вісь читала файл ЗАНОВО і фільтрувала
    # всі ~1500 рядків без жодних меж, хоч і шапка, і текст помилки, і рядок успіху
    # кажуть «§10» (adversarial 2026-08-20). Наслідки були обабіч: рядок, винесений
    # із §10 куди завгодно, лишав гейт зеленим при ПОРОЖНІЙ §10, а приклад-рядок у
    # туторіальній частині червонив із ХИБНОЮ адресою в повідомленні.
    # `heading_index` кидає, а не мовчить, коли заголовок зникає — саме тому він тут.
    preview_doc  = registry_previews(doc_lines)
    errors += compare("Lookbook preview", preview_code, preview_doc,
                      "#{PREVIEWS_REL}/", "04_04 §10")

    dir_namespaces = Dir.children(components_dir)
                        .select { |c| File.directory?(File.join(components_dir, c)) }
                        .to_set
    errors += compare("§1 tree namespace", dir_namespaces, tree_namespaces(doc_lines),
                      "#{COMPONENTS_REL}/", "the 04_04 §1 hierarchy tree")

    errors
  end

  # Counts for the success line — computed from the same sources as `audit`, so
  # a green run cannot report numbers the audit did not actually inspect.
  def summary(root)
    doc_lines = File.readlines(File.join(root, DOC_REL), chomp: true)
    {
      domain: code_classes(File.join(root, COMPONENTS_REL), nested: true,
                           reject: NON_COMPONENT_BASENAMES).size,
      namespaces: tree_namespaces(doc_lines).size,
      previews: Dir.glob(File.join(root, PREVIEWS_REL, "*_preview.rb")).size
    }
  end
end

if __FILE__ == $PROGRAM_NAME
  root   = File.expand_path("..", __dir__)
  errors = ComponentDocSync.audit(root)

  if errors.empty?
    counts = ComponentDocSync.summary(root)
    puts "component_doc_sync ✓ — 04_04 ⟷ app/views (#{counts[:domain]} domain components in §6.4, " \
         "#{counts[:namespaces]} namespaces in the §1 tree, #{counts[:previews]} Lookbook previews in §10, " \
         "shared/ui+iot+web3 registries in sync)"
    exit 0
  else
    warn "component_doc_sync ✗ — 04_04 ↔ app/views drift:"
    errors.each { |e| warn "  · #{e}" }
    warn ""
    warn "The registry writes components in three row forms (see this script's header)."
    warn "Registry home: docs/04_04_Phlex_UI_and_Tailwind.md §6 · placement rule: §6.5"
    exit 1
  end
end
