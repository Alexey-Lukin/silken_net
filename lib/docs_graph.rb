# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "set"

# DocsGraph — read-only reference-graph analyzer for the SSOT canon
# (docs/NN_NN_*.md). A code call-graph models code, but not our NN_NN
# doc-link convention, so this is the docs' own directed reference graph:
#   nodes = canon docs (id "NN_NN")
#   edges = a `](NN_NN_Name)` markdown link from one doc to another.
#
# It surfaces what a flat linter cannot: orphan / weakly-discoverable pages,
# in/out-degree skew, one-way (asymmetric) links between siblings, and — beyond
# the linked-§ drift guard — a comprehensive `#anchor` validation pass against
# the GitHub-slug heading set (the ToC's own SSOT, lib/docs_toc.rb).
#
# Pure functions (unit-tested in spec/lib/docs_graph_spec.rb), mirroring the
# lib/docs_linter.rb engine pattern: module_function, takes parsed inputs
# (id→text), returns plain data — no Rails, no file I/O. Wired + printed by
# rake docs:graph (read-only; not a CI gate).
module DocsGraph
  module_function

  # Target-id of every cross-doc link `](NN_NN_Name)` / `](NN_NN_Name#anchor)`.
  DOC_LINK_RE = /\]\((\d\d_\d\d)_[A-Za-z0-9_]+(?:#[^)]*)?\)/
  # Index / tracker are structural hubs: 00_00 links OUT to every page, 00_07 is
  # linked-by nearly every page. Counting them would drown the content-web
  # signal, so orphan/asymmetry analyses exclude them (degree table keeps them).
  HUB_IDS = %w[00_00 00_07].freeze

  # id → Set of distinct *other* canon ids it links to (self-links dropped).
  def out_edges(docs)
    valid = docs.keys.to_set
    docs.to_h do |id, text|
      targets = text.scan(DOC_LINK_RE).flatten.to_set & valid
      targets.delete(id)
      [ id, targets ]
    end
  end

  # id → Set of distinct canon ids that link TO it (reverse of out_edges).
  def in_edges(docs)
    incoming = docs.keys.to_h { |id| [ id, Set.new ] }
    out_edges(docs).each { |src, tgts| tgts.each { |t| incoming[t] << src } }
    incoming
  end

  # Per-node degree rows sorted by id. `content_in` = in-degree excluding the
  # structural hubs (a page only the index/tracker points to is barely woven in).
  def degrees(docs)
    out = out_edges(docs)
    inc = in_edges(docs)
    docs.keys.sort.map do |id|
      { id: id, out: out[id].size, in: inc[id].size,
        content_in: (inc[id] - HUB_IDS).size }
    end
  end

  # Orphan / weakly-discoverable: a non-hub page with content_in == 0 — reachable
  # only via the index/tracker, never cited by a sibling. Returns degree rows.
  def orphans(docs)
    degrees(docs).reject { |r| HUB_IDS.include?(r[:id]) }.select { |r| r[:content_in].zero? }
  end

  # Dead-ends: a non-hub doc linking to NO other canon doc (out == 0) — unusual
  # for canon, which should at least cite its 00_07 tracker / siblings.
  def dead_ends(docs)
    degrees(docs).reject { |r| HUB_IDS.include?(r[:id]) }.select { |r| r[:out].zero? }
  end

  # One-way (asymmetric) edges A→B where B does not link back, both non-hub.
  # Not every link needs reciprocation, so this is advisory — it spots a sibling
  # that references another but is never referenced back (a candidate backlink).
  # Returns sorted [[a, b], ...].
  def asymmetric_edges(docs)
    out = out_edges(docs)
    out.flat_map do |a, tgts|
      next [] if HUB_IDS.include?(a)
      tgts.reject { |b| HUB_IDS.include?(b) || out[b].include?(a) }.map { |b| [ a, b ] }
    end.sort
  end

  # GitHub heading-anchor slug — mirrors DocsToc.github_anchor (the ToC's SSOT)
  # but ALSO keeps subscript/superscript digits (`\p{No}`, e.g. `x₀`), which
  # github-slugger preserves and DocsToc drops. No ToC H2 carries a subscript, so
  # this never diverges on a real ToC anchor; it only stops math H3s (03_04
  # `(x₀, y₀, z₀)`) from false-flagging in the #anchor check.
  def gh_anchor(text)
    s = text.strip.downcase
    s = s.gsub(/[^\p{Word}\p{No}\- ]/u, "")
    s = s.gsub(/[\p{Mn}\p{Me}\p{Cf}]/u, "")
    s.gsub(" ", "-")
  end

  # GitHub-anchor set for a doc: the slug of every heading (all levels), with
  # GitHub's duplicate-slug disambiguation (`-1`, `-2`, … in document order).
  # Lines inside ``` fences are skipped (a `# comment` there is not a heading).
  HEADING_LINE_RE = /\A(\#{1,6})\s+(.+?)\s*\z/

  def anchor_set(text)
    counts = Hash.new(0)
    set = Set.new
    in_fence = false
    text.each_line do |line|
      in_fence = !in_fence if line.start_with?("```")
      next if in_fence

      m = HEADING_LINE_RE.match(line)
      next unless m

      base = gh_anchor(m[2])
      n = counts[base]
      counts[base] += 1
      set << (n.zero? ? base : "#{base}-#{n}")
    end
    set
  end

  # Comprehensive `#anchor` validation: every link carrying a `#fragment` — both
  # intra-doc `](#frag)` and cross-doc `](NN_NN_Name#frag)` — must resolve to a
  # real heading anchor in the target. A stale anchor silently lands the reader
  # at the top of the page; the linked-§ drift guard never sees it. `anchors` is
  # id → anchor_set(text). Returns [{from:, to:, anchor:}], sorted. Cross-doc
  # links to an absent target are left to the dangling-link guard (skipped here).
  # Lines inside ``` fences are skipped, so a markdown EXAMPLE of an anchor link
  # (`[text](#some-anchor)`) in a fenced code block is not a false positive — this
  # matters now that the check is a HARD CI gate (docs:check_refs), not just an audit.
  ANCHOR_LINK_RE = /\]\((\d\d_\d\d_[A-Za-z0-9_]+)?#([^)\s]+)\)/

  def dangling_anchors(docs, anchors)
    docs.flat_map do |id, text|
      in_fence = false
      text.each_line.flat_map do |line|
        in_fence = !in_fence if line.start_with?("```")
        next [] if in_fence

        line.scan(ANCHOR_LINK_RE).filter_map do |target_file, frag|
          target = target_file ? target_file[/\A\d\d_\d\d/] : id
          next unless anchors.key?(target) # unknown target → dangling-link guard's job

          { from: id, to: target, anchor: frag } unless anchors[target].include?(frag)
        end
      end
    end.sort_by { |h| [ h[:from], h[:to], h[:anchor] ] }
  end
end
