# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "spec_helper"
require_relative "../../scripts/sbom_merge"

# [BIZ.24] Unit coverage for the CycloneDX fragment merger. Pure functions, no
# Rails/DB. The three behaviours worth testing are the three reasons this exists
# instead of `cyclonedx-cli merge`: spec-version cannot drift, an input's
# metadata-component is NOT demoted into components, and a conflicting duplicate
# is reported rather than silently collapsed.
RSpec.describe SbomMerge do
  def fragment(components, spec: "1.6", meta_name: "scan-subject")
    {
      "bomFormat" => "CycloneDX", "specVersion" => spec, "version" => 1,
      "metadata" => { "component" => { "type" => "application", "name" => meta_name } },
      "components" => components
    }
  end

  def comp(name, purl: nil, version: "1.0.0", extra: {})
    { "type" => "library", "name" => name, "version" => version }
      .merge(purl ? { "purl" => purl } : {}).merge(extra)
  end

  describe ".dedup_key" do
    it "prefers purl" do
      expect(described_class.dedup_key(comp("a", purl: "pkg:conda/a@1"))).to eq("pkg:conda/a@1")
    end

    it "falls back to bom-ref, then to group/name/version" do
      expect(described_class.dedup_key({ "bom-ref" => "ref-1", "name" => "a" })).to eq("ref-1")
      expect(described_class.dedup_key({ "group" => "g", "name" => "a", "version" => "2" }))
        .to eq("g/a/2")
    end
  end

  describe ".build" do
    it "keeps specVersion 1.6 and names the AGGREGATE, not an input" do
      r = described_class.build([ fragment([ comp("a", purl: "pkg:conda/a@1") ]) ],
                                name: "silken_net", version: "v9")
      expect(r[:document]["specVersion"]).to eq("1.6")
      expect(r[:document]["metadata"]["component"]["name"]).to eq("silken_net")
    end

    it "does NOT demote an input's metadata.component into components" do
      # The reason the official merger reports 529 for 10 + 517: each fragment's
      # scan subject becomes a listed dependency. A scan subject is not a dependency.
      r = described_class.build(
        [ fragment([ comp("a", purl: "pkg:conda/a@1") ], meta_name: "conda-env"),
          fragment([ comp("b", purl: "pkg:github/o/b@sha") ], meta_name: "repo") ],
        name: "agg", version: "v1"
      )
      names = r[:document]["components"].map { |c| c["name"] }
      expect(names).to contain_exactly("a", "b")
      expect(names).not_to include("conda-env", "repo")
    end

    it "collapses identical duplicates without reporting a collision" do
      dup = comp("a", purl: "pkg:conda/a@1")
      r = described_class.build([ fragment([ dup ]), fragment([ dup.dup ]) ], name: "x", version: "1")
      expect(r[:document]["components"].size).to eq(1)
      expect(r[:collisions]).to be_empty
    end

    it "collapses twins differing ONLY by bom-ref — the shape that actually occurs" do
      # The example above copies a body literally, which no scanner ever emits:
      # `bom-ref` is a document-local pointer and Trivy mints a fresh UUID per row,
      # so a real duplicate ALWAYS differs somewhere. Comparing it compared the
      # pointer instead of the artefact and failed `--assert` on benign input — the
      # 7 conda packages shared by tools/in_silico and tools/ml, all from ONE Trivy
      # fragment, bodies identical in everything but the UUID.
      a = comp("numpy", purl: "pkg:conda/numpy", extra: { "bom-ref" => "uuid-1" })
      b = comp("numpy", purl: "pkg:conda/numpy", extra: { "bom-ref" => "uuid-2" })
      r = described_class.build([ fragment([ a, b ]) ], name: "x", version: "1")
      expect(r[:collisions]).to be_empty
      expect(r[:document]["components"].size).to eq(1)
    end

    it "collapses one scanner reaching a package through two analysers" do
      # Same name+version+purl, differing only in the tool's own `properties`:
      # Trivy finds a NuGet package both in the resolved `.deps.json` graph and in
      # Central Package Management. That is provenance — both true at once — not two
      # scanners disagreeing. Observed on a newer Trivy than the CI pin, so this
      # example is what keeps the next `trivy-action` bump from failing a release.
      props = ->(v) { [ { "name" => "aquasecurity:trivy:PkgType", "value" => v } ] }
      a = comp("PicoGK", purl: "pkg:nuget/PicoGK@2.2.0", version: "2.2.0",
               extra: { "bom-ref" => "uuid-1", "properties" => props.call("dotnet-core") })
      b = comp("PicoGK", purl: "pkg:nuget/PicoGK@2.2.0", version: "2.2.0",
               extra: { "bom-ref" => "uuid-2", "properties" => props.call("packages-props") })
      r = described_class.build([ fragment([ a, b ]) ], name: "x", version: "1")
      expect(r[:collisions]).to be_empty
      expect(r[:document]["components"].size).to eq(1)
    end

    it "still reports a real conflict even when bom-refs also differ" do
      # The other direction: excluding `bom-ref` must not blind the guard. Same key,
      # genuinely different content (differing hashes) stays a reported collision.
      a = comp("a", purl: "pkg:conda/a@1",
               extra: { "bom-ref" => "uuid-1", "hashes" => [ { "alg" => "SHA-256", "content" => "aa" } ] })
      b = comp("a", purl: "pkg:conda/a@1",
               extra: { "bom-ref" => "uuid-2", "hashes" => [ { "alg" => "SHA-256", "content" => "bb" } ] })
      r = described_class.build([ fragment([ a ]), fragment([ b ]) ], name: "x", version: "1")
      expect(r[:collisions]).to eq([ "pkg:conda/a@1" ])
    end

    it "reports a collision when one key carries two different bodies" do
      # Two scanners describing the same artefact differently is a fact worth
      # surfacing — collapsing it would pick a winner at random.
      a = comp("a", purl: "pkg:conda/a@1", extra: { "hashes" => [ { "alg" => "SHA-256", "content" => "aa" } ] })
      b = comp("a", purl: "pkg:conda/a@1", extra: { "hashes" => [ { "alg" => "SHA-256", "content" => "bb" } ] })
      r = described_class.build([ fragment([ a ]), fragment([ b ]) ], name: "x", version: "1")
      expect(r[:collisions]).to eq([ "pkg:conda/a@1" ])
      expect(r[:document]["components"].size).to eq(1)
    end

    it "sorts components deterministically" do
      r = described_class.build(
        [ fragment([ comp("z", purl: "pkg:conda/z@1"), comp("a", purl: "pkg:conda/a@1") ]) ],
        name: "x", version: "1"
      )
      expect(r[:document]["components"].map { |c| c["name"] }).to eq(%w[a z])
    end
  end

  describe ".timestamp" do
    it "honours SOURCE_DATE_EPOCH so a rerun is byte-identical" do
      ENV["SOURCE_DATE_EPOCH"] = "1700000000"
      expect(described_class.timestamp).to eq("2023-11-14T22:13:20Z")
    ensure
      ENV.delete("SOURCE_DATE_EPOCH")
    end
  end

  describe ".load_fragment" do
    def write(dir, name, doc)
      path = File.join(dir, name)
      File.write(path, JSON.generate(doc))
      path
    end

    def with_fragment(name, doc)
      require "tmpdir"
      Dir.mktmpdir { |dir| yield write(dir, name, doc) }
    end

    it "refuses a fragment declaring a different specVersion" do
      with_fragment("x.json", fragment([], spec: "1.7")) do |path|
        expect { described_class.load_fragment(path) }
          .to raise_error(/specVersion "1.7", expected 1.6/)
      end
    end

    it "refuses a non-CycloneDX document" do
      with_fragment("y.json", { "bomFormat" => "SPDX" }) do |path|
        expect { described_class.load_fragment(path) }.to raise_error(/not a CycloneDX document/)
      end
    end
  end
end
