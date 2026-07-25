#!/usr/bin/env ruby
# frozen_string_literal: true

# [BIZ.24] Flat merge of CycloneDX-1.6 fragments into one aggregate SBOM.
#
# WHY OUR OWN MERGE instead of `cyclonedx-cli merge` (which exists and works):
#   1. **Pinning.** Repo policy (00_05 §2.7) pins every external `uses:` to a
#      40-char commit SHA and every CLI analyser to a verified sha256. The
#      official merger ships as a container; adding it would mean carrying an
#      image digest for ~40 lines of set-union. Ruby stdlib needs no pin.
#   2. **specVersion drift.** Verified empirically: `cyclonedx merge` emits
#      **1.7** by default, so the aggregate silently leaves the version its
#      inputs declared unless `--output-version v1_6` is passed. Our merge cannot
#      drift — it asserts every input is 1.6 and writes 1.6.
#   3. **Component-count inflation.** In that tool each input's
#      `metadata.component` (the repo itself, the conda env) is demoted into
#      `components[]`, so merging two fragments of 10 + 517 yields 529, not 527.
#      Here `metadata.component` describes the AGGREGATE and inputs' own
#      metadata-components are dropped — they are descriptions of a scan, not
#      dependencies of the product.
#
# Dedup key = `purl` when present, else `bom-ref`, else `name@version`. Fragments
# are disjoint by construction (different purl namespaces), so a collision means
# two scanners claimed the same artefact — that is worth REPORTING, not silently
# collapsing: `--assert` fails on any conflicting duplicate (same key, different
# content) while identical duplicates collapse quietly.
#
# NAMED CEILING [BIZ.24]: this is a FLAT merge. No `dependencies[]` graph is
# produced or preserved — conda-lock carries ranges, not resolved bom-refs, and
# faking a graph is worse than declaring none (CRA Annex I Part II asks for
# components "covering at the very least the top-level dependencies", not a
# resolved graph).
#
# `SOURCE_DATE_EPOCH` is honoured so a rerun is byte-identical.
#
# Pure Ruby stdlib (json). Usage:
#   ruby scripts/sbom_merge.rb a.cdx.json b.cdx.json --name silken_net \
#        --version v1.2.3 --output silken_net.cdx.json [--assert]

require "json"

module SbomMerge
  SPEC_VERSION = "1.6"

  module_function

  def dedup_key(component)
    component["purl"] ||
      component["bom-ref"] ||
      [ component["group"], component["name"], component["version"] ].compact.join("/")
  end

  # Returns { components:, collisions: } — collisions = same key, different body.
  def combine(fragments)
    seen = {}
    collisions = []

    fragments.each do |frag|
      (frag["components"] || []).each do |c|
        k = dedup_key(c)
        if seen.key?(k)
          collisions << k unless seen[k] == c
        else
          seen[k] = c
        end
      end
    end

    { components: seen.values.sort_by { |c| dedup_key(c).to_s }, collisions: collisions.uniq }
  end

  def timestamp
    epoch = ENV["SOURCE_DATE_EPOCH"]
    (epoch ? Time.at(Integer(epoch)) : Time.now).utc.strftime("%Y-%m-%dT%H:%M:%SZ")
  end

  def build(fragments, name:, version:)
    r = combine(fragments)
    doc = {
      "bomFormat" => "CycloneDX",
      "specVersion" => SPEC_VERSION,
      "version" => 1,
      "metadata" => {
        "timestamp" => timestamp,
        "component" => {
          "type" => "application",
          "bom-ref" => "#{name}@#{version}",
          "name" => name,
          "version" => version
        },
        "tools" => [ { "name" => "sbom_merge.rb", "vendor" => "SilkenNet" } ]
      },
      "components" => r[:components]
    }
    { document: doc, collisions: r[:collisions] }
  end

  def load_fragment(path)
    doc = JSON.parse(File.read(path))
    unless doc["bomFormat"] == "CycloneDX"
      raise "#{path}: not a CycloneDX document (bomFormat=#{doc['bomFormat'].inspect})"
    end
    unless doc["specVersion"] == SPEC_VERSION
      raise "#{path}: specVersion #{doc['specVersion'].inspect}, expected #{SPEC_VERSION} " \
            "(an aggregate must not silently change spec version)"
    end

    doc
  end
end

if __FILE__ == $PROGRAM_NAME
  args = ARGV.dup
  assert = !args.delete("--assert").nil?
  opt = ->(flag) { (i = args.index(flag)) ? args.slice!(i, 2)[1] : nil }
  out = opt.call("--output")
  name = opt.call("--name") || "silken_net"
  version = opt.call("--version") || "0.0.0-dev"
  inputs = args.reject { |a| a.start_with?("-") }

  abort "sbom_merge: no input fragments given" if inputs.empty?

  begin
    fragments = inputs.map { |p| SbomMerge.load_fragment(p) }
  rescue StandardError => e
    warn "sbom_merge ✗ — #{e.message}"
    exit 1
  end

  r = SbomMerge.build(fragments, name:, version:)
  json = JSON.pretty_generate(r[:document])
  out ? File.write(out, "#{json}\n") : puts(json)

  warn "sbom_merge — #{inputs.size} fragment(s) → #{r[:document]['components'].size} component(s), " \
       "CycloneDX #{SbomMerge::SPEC_VERSION}"

  unless r[:collisions].empty?
    warn "sbom_merge ✗ — #{r[:collisions].size} conflicting duplicate(s) (same key, different body):"
    r[:collisions].each { |k| warn "  · #{k}" }
    warn "Two scanners describe one artefact differently — reconcile, do not collapse."
    exit 1 if assert
  end

  exit 0
end
