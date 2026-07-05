# frozen_string_literal: true

# docs:graph — read-only reference-graph audit of the SSOT canon (00_06 §3
# tooling). Complements docs:check_refs (flat per-line drift gates) with the
# graph view flat per-line linters can't give us (they check refs, not the NN_NN link graph):
# orphan / weakly-discoverable pages, in/out-degree skew, one-way sibling links,
# and a comprehensive #anchor + cross-doc §-ref validation. Engine:
# lib/docs_graph.rb (+ DocsLinter.section_label_drift), both unit-tested.
# Prints a report; does NOT gate CI (analysis tool — run on demand / round-N).
require_relative "../docs_graph"
require_relative "../docs_linter"

DOCS_GRAPH_GLOB = File.expand_path("../../docs/[0-9][0-9]_[0-9][0-9]_*.md", __dir__)

namespace :docs do
  desc "Ref-graph audit: orphans, in/out-degree, one-way links, #anchor + §-ref validation"
  task :graph do
    files = Dir.glob(DOCS_GRAPH_GLOB).sort
    docs = files.to_h { |f| [ File.basename(f)[/\A\d\d_\d\d/], File.read(f) ] }
    # NB: section_label_drift does a SUBSTRING `.include?` on a joined heading
    # STRING (mirrors docs.rake) — keyed by full basename, as the §-guard expects.
    headings = files.to_h do |f|
      [ File.basename(f, ".md"), File.readlines(f).grep(/\A#+\s/).join("\n").downcase ]
    end
    anchors = docs.transform_values { |t| DocsGraph.anchor_set(t) }

    degrees   = DocsGraph.degrees(docs)
    out_edges = DocsGraph.out_edges(docs)
    total_edges = out_edges.values.sum(&:size)
    oneway_edges = DocsGraph.asymmetric_edges(docs)
    nonhub = ->(x) { !DocsGraph::HUB_IDS.include?(x) }
    # mutual pairs counted once (b > a) among non-hub nodes that link both ways.
    mutual_pairs = out_edges.sum do |a, ts|
      nonhub.call(a) ? ts.count { |b| nonhub.call(b) && b > a && out_edges[b].include?(a) } : 0
    end

    puts "docs:graph — #{docs.size} canon nodes, #{total_edges} cross-doc links"
    puts "  content edges: #{mutual_pairs} mutual pairs · #{oneway_edges.size} one-way (non-hub)"
    puts

    # ---- Orphans / weak discoverability ----
    orphans = DocsGraph.orphans(docs)
    if orphans.empty?
      puts "  orphans:        none — every page cited by a non-hub sibling ✓"
    else
      puts "  ⚠️ orphan / index-only pages (#{orphans.size}) — only the index/tracker cite them:"
      orphans.each { |r| puts "      #{r[:id]}  (in=#{r[:in]} content_in=0 out=#{r[:out]})" }
    end

    # ---- Dead-ends ----
    dead = DocsGraph.dead_ends(docs)
    if dead.empty?
      puts "  dead-ends:      none — every page links out ✓"
    else
      puts "  ⚠️ dead-end pages (#{dead.size}) — link to no other canon doc:"
      dead.each { |r| puts "      #{r[:id]}  (in=#{r[:in]} out=0)" }
    end
    puts

    # ---- Degree extremes (orientation, not a defect) ----
    top_in  = degrees.reject { |r| DocsGraph::HUB_IDS.include?(r[:id]) }.max_by(5) { |r| r[:content_in] }
    low_in  = degrees.reject { |r| DocsGraph::HUB_IDS.include?(r[:id]) }.select { |r| r[:content_in] <= 1 }
    puts "  most-referenced (content_in): " + top_in.map { |r| "#{r[:id]}=#{r[:content_in]}" }.join(" · ")
    puts "  thinly-referenced (content_in≤1): " + (low_in.empty? ? "none" : low_in.map { |r| "#{r[:id]}=#{r[:content_in]}" }.join(" · "))
    puts

    # ---- Dangling #anchors (NEW — beyond linked-§ drift) ----
    danchors = DocsGraph.dangling_anchors(docs, anchors)
    if danchors.empty?
      puts "  #anchors:       every #fragment resolves to a heading ✓"
    else
      puts "  ✗ dangling #anchors (#{danchors.size}) — fragment has no matching heading slug:"
      danchors.each { |h| puts "      #{h[:from]} → #{h[:to]}##{h[:anchor]}" }
    end

    # ---- Cross-doc §-label validation (comprehensive; reuses the drift rule) ----
    sec = docs.flat_map { |id, text| DocsLinter.section_label_drift(text, headings).map { |h| "#{id}: #{h}" } }.uniq
    if sec.empty?
      puts "  §-refs:         every linked `§X` resolves to a heading ✓"
    else
      puts "  ⚠️ §-label drift (#{sec.size}) — linked §X with no matching heading:"
      sec.each { |s| puts "      #{s}" }
    end

    # ---- One-way edge listing (advisory; candidate backlinks) ----
    unless oneway_edges.empty?
      puts
      puts "  one-way content links (#{oneway_edges.size}) — A→B with no B→A (candidate backlinks):"
      oneway_edges.each_slice(6) { |row| puts "      " + row.map { |a, b| "#{a}→#{b}" }.join("  ") }
    end
  end
end
