#!/usr/bin/env ruby
# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [BIZ.24] Flat merge of CycloneDX-1.6 fragments into one aggregate SBOM.
#
# WHY OUR OWN MERGE instead of `cyclonedx-cli merge` (which exists and works):
#   1. **Pinning.** Repo policy (06_07 §1a) pins every external `uses:` to a
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
# Dedup key = `purl` when present, else `bom-ref`, else `name@version`. A collision
# means one key carries two DIFFERENT bodies — worth REPORTING, not silently
# collapsing, because collapsing picks a winner at random: `--assert` fails on any
# conflicting duplicate while identical ones collapse quietly.
#
# 🔴 Duplicates are NOT only cross-fragment. This merge walks every component of
# every fragment, and one scanner reading two manifests produces them on its own:
# Trivy emits a row per `environment.yml` entry, so the 7 packages shared by
# `tools/in_silico` and `tools/ml` arrive twice from a single Trivy fragment. An
# earlier note here claimed fragments were "disjoint by construction" and that a
# collision therefore meant two scanners disagreeing — both halves were false.
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

  # What makes two rows THE SAME ARTEFACT — i.e. what a collision must ignore.
  # Both excluded fields are TOOL BOOKKEEPING, not properties of the thing:
  #
  #   · `bom-ref` — a document-local pointer. Trivy mints a fresh UUID per row, so
  #     two rows for one package are never `==` even when otherwise byte-identical.
  #     Comparing it compares the pointer instead of the thing, which made the
  #     "identical duplicates collapse quietly" promise unreachable for any such
  #     scanner. Verified, not assumed: one Trivy run over our two `environment.yml`
  #     files produced exactly 7 pairs — the intersection of the two envs — differing
  #     in `bom-ref` and NOTHING else, and `--assert` failed the release on them.
  #   · `properties` — CycloneDX's explicit vendor-extension store. One scanner can
  #     reach one package through two analysers and disagree only with itself there:
  #     `PkgType=dotnet-core` (resolved `.deps.json`) vs `packages-props` (Central
  #     Package Management) for the same name+version+purl. That is provenance, not
  #     disagreement — both are true at once.
  #
  # NAMED CEILING: a scanner that encodes a load-bearing fact ONLY in `properties`
  # would have a genuine disagreement collapse silently here. Accepted, because every
  # identity-bearing field — `purl`, `version`, `name`, `type`, `hashes`, `licenses` —
  # is still compared; `properties` is by spec the place tools put their own notes.
  #
  # Dropping a twin is safe because the aggregate carries no `dependencies[]` graph
  # (NAMED CEILING above) — no surviving ref can dangle.
  IGNORED_IN_COMPARISON = %w[bom-ref properties].freeze

  def semantic_body(component)
    component.reject { |k, _| IGNORED_IN_COMPARISON.include?(k) }
  end

  # Returns { components:, collisions: } — collisions = same key, different body.
  def combine(fragments)
    seen = {}
    collisions = []

    fragments.each do |frag|
      (frag["components"] || []).each do |c|
        k = dedup_key(c)
        if seen.key?(k)
          collisions << k unless semantic_body(seen[k]) == semantic_body(c)
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
