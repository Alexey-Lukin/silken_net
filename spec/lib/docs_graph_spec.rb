# frozen_string_literal: true

require_relative "../spec_helper"
require_relative "../../lib/docs_graph"

# Pure-function units for the SSOT ref-graph analyzer (no Rails/DB).
# Run gate-free: COVERAGE=0 bin/rspec spec/lib/docs_graph_spec.rb
RSpec.describe DocsGraph do
  # A tiny canon: 01_01 ↔ 01_02 (mutual); 01_01 → 03_04 and 03_04 → 01_02
  # (one-way); 00_00 index → everything; 05_05 orphan (index-only) + dead-end.
  let(:docs) do
    {
      "00_00" => "index → [a](01_01_A) [b](01_02_B) [c](03_04_C) [d](05_05_D)",
      "01_01" => "see [B](01_02_B) and [Lorenz](03_04_C) and self [x](01_01_A)",
      "01_02" => "back to [A](01_01_A) only",
      "03_04" => "owner doc, links out to [B](01_02_B)",
      "05_05" => "policy prose, no canon links at all"
    }
  end

  describe ".out_edges" do
    it "maps each doc to distinct other-doc targets, dropping self-links" do
      out = described_class.out_edges(docs)
      expect(out["01_01"]).to contain_exactly("01_02", "03_04") # self 01_01 dropped
      expect(out["05_05"]).to be_empty
      expect(out["00_00"]).to contain_exactly("01_01", "01_02", "03_04", "05_05")
    end
  end

  describe ".in_edges" do
    it "reverses the adjacency and lists every node as a key" do
      inc = described_class.in_edges(docs)
      expect(inc["01_01"]).to contain_exactly("00_00", "01_02") # 03_04 no longer cites 01_01
      expect(inc["05_05"]).to contain_exactly("00_00")
      expect(inc.keys).to match_array(docs.keys)
    end
  end

  describe ".degrees" do
    it "computes out / in / content_in (content_in excludes hubs)" do
      row = described_class.degrees(docs).find { |r| r[:id] == "05_05" }
      expect(row).to include(out: 0, in: 1, content_in: 0) # in-edge is 00_00 hub only
    end
  end

  describe ".orphans" do
    it "flags a non-hub page cited only by the index/tracker" do
      expect(described_class.orphans(docs).map { |r| r[:id] }).to contain_exactly("05_05")
    end
  end

  describe ".dead_ends" do
    it "flags a non-hub page that links to no other canon doc" do
      expect(described_class.dead_ends(docs).map { |r| r[:id] }).to contain_exactly("05_05")
    end
  end

  describe ".asymmetric_edges" do
    it "returns one-way non-hub edges (A→B without B→A), excluding hub edges" do
      # 01_01↔01_02 mutual (absent); 01_01→03_04 one-way present; hub edges excluded
      expect(described_class.asymmetric_edges(docs)).to include(%w[01_01 03_04])
      expect(described_class.asymmetric_edges(docs)).not_to include(%w[01_01 01_02])
      expect(described_class.asymmetric_edges(docs).flatten).not_to include("00_00")
    end
  end

  describe ".anchor_set" do
    it "slugs every heading level with GitHub duplicate disambiguation, skipping fences" do
      text = <<~MD
        # Title
        ## 📐 1. Alpha
        ### Sub
        ## 1. Alpha
        ```
        ## Not A Heading (fenced)
        ```
      MD
      set = described_class.anchor_set(text)
      expect(set).to include("title", "-1-alpha", "sub")
      expect(set).to include("1-alpha")            # first plain "1. Alpha"
      expect(set).not_to include("not-a-heading-fenced") # inside ``` fence
    end

    it "disambiguates repeated slugs with -1, -2 in document order" do
      set = described_class.anchor_set("## Dup\n## Dup\n## Dup\n")
      expect(set).to contain_exactly("dup", "dup-1", "dup-2")
    end

    it "keeps subscript digits (\\p{No}) like github-slugger (03_04 x₀ math headings)" do
      expect(described_class.anchor_set("### Координат `(x₀, y₀, z₀)`")).to include("координат-x₀-y₀-z₀")
    end
  end

  describe ".dangling_anchors" do
    let(:adocs) do
      {
        "01_01" => "## Real Heading\nintra ok [x](#real-heading) intra bad [y](#ghost) cross ok [z](03_04_C#owner-sec)",
        "03_04" => "## Owner Sec\nbody"
      }
    end
    let(:anchors) { adocs.transform_values { |t| described_class.anchor_set(t) } }

    it "flags only fragments with no matching heading slug (intra- and cross-doc)" do
      result = described_class.dangling_anchors(adocs, anchors)
      expect(result.map { |h| h[:anchor] }).to contain_exactly("ghost") # #real-heading + #owner-sec resolve
    end

    it "skips anchor-link examples inside ``` fences (HARD-gate FP guard)" do
      fenced = {
        "01_01" => "## Real Heading\n```md\nexample: [x](#never-real-anchor)\n```\nprose [y](#real-heading)\n"
      }
      asets = fenced.transform_values { |t| described_class.anchor_set(t) }
      expect(described_class.dangling_anchors(fenced, asets)).to be_empty
    end

    it "skips a cross-doc anchor link whose target doc isn't in the anchors set (dangling-link guard's job)" do
      docs = { "01_01" => "## Real Heading\nsee [x](99_99_Ghost_Doc#some-anchor)\n" }
      anchors = { "01_01" => described_class.anchor_set(docs["01_01"]) }
      expect(described_class.dangling_anchors(docs, anchors)).to be_empty
    end
  end
end
