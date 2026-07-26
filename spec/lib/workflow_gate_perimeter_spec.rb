# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../../scripts/workflow_gate_perimeter"

# [OPS.14] Unit coverage for the gate-perimeter meta-guard. Pure functions +
# fixture-tree audits (no Rails/DB); the same module the CLI wraps. Mirrors the
# no-Rails, fixture-driven style of the other standalone script-guards.
RSpec.describe WorkflowGatePerimeter do
  # Build a throwaway `.github/workflows/` tree; yields the fake repo root.
  def with_workflows(files)
    Dir.mktmpdir do |root|
      dir = File.join(root, WorkflowGatePerimeter::WF_DIR)
      FileUtils.mkdir_p(dir)
      files.each { |name, body| File.write(File.join(dir, name), body) }
      yield root
    end
  end

  # A minimal pull_request-triggered workflow with no aggregate job.
  def pr_job
    <<~YAML
      on:
        pull_request:
      jobs:
        build:
          name: some job
          runs-on: ubuntu-latest
    YAML
  end

  # An `if: always()` aggregate whose name is the branch-protection label.
  def required_wf(label)
    <<~YAML
      on:
        pull_request:
      jobs:
        agg:
          name: #{label}
          if: ${{ always() }}
          runs-on: ubuntu-latest
    YAML
  end

  describe ".pr_triggered?" do
    it "detects the YAML-1.1 bare-`on:`→boolean-true quirk" do
      # Psych parses bare `on:` as the key `true`, not the string "on".
      yaml = YAML.safe_load("on:\n  pull_request:\njobs: {}")
      expect(yaml).to have_key(true)          # guards the premise
      expect(described_class.pr_triggered?(yaml)).to be(true)
    end

    it "accepts the array form and rejects push-only / pull_request_target-only" do
      expect(described_class.pr_triggered?("on" => %w[pull_request push])).to be(true)
      expect(described_class.pr_triggered?("on" => { "push" => nil })).to be(false)
      # pull_request_target (labeler.yml) is a privileged automation, NOT a gate.
      expect(described_class.pr_triggered?("on" => { "pull_request_target" => nil })).to be(false)
    end
  end

  describe ".always_aggregate?" do
    let(:yaml) { YAML.safe_load(required_wf("CI passed")) }

    it "matches a named always() aggregate (both `${{ always() }}` and `always()`)" do
      expect(described_class.always_aggregate?(yaml, "CI passed")).to be(true)
      bare = YAML.safe_load("jobs:\n  agg:\n    name: X\n    if: always()")
      expect(described_class.always_aggregate?(bare, "X")).to be(true)
    end

    it "rejects when the name mismatches or always() is absent" do
      expect(described_class.always_aggregate?(yaml, "Docs passed")).to be(false)
      no_always = YAML.safe_load("jobs:\n  agg:\n    name: X\n    if: success()")
      expect(described_class.always_aggregate?(no_always, "X")).to be(false)
    end
  end

  describe ".audit — the real repo (regression guard)" do
    subject(:result) { described_class.audit }

    it "reports a sound perimeter: no HARD errors" do
      expect(result[:errors]).to be_empty
    end

    it "classifies exactly the pull_request-triggered workflows" do
      expect(result[:pr_workflows]).to match_array(WorkflowGatePerimeter::PERIMETER.keys)
    end

    it "surfaces the flip_pending workflows as advisories (never errors)" do
      flips = WorkflowGatePerimeter::PERIMETER.select { |_b, (c, _)| c == :flip_pending }.keys
      expect(result[:advisories].size).to eq(flips.size)
    end
  end

  describe ".audit — fixture HARD checks" do
    let(:perimeter) do
      { "req.yml" => [ :required, "Fixture passed" ], "flip.yml" => [ :flip_pending, "FLIP.1" ] }
    end

    it "(a) a NEW unclassified pull_request-gate → error" do
      with_workflows("req.yml" => required_wf("Fixture passed"),
                     "flip.yml" => pr_job,
                     "newbie.yml" => pr_job) do |root|
        errors = described_class.audit(root:, perimeter:)[:errors]
        expect(errors).to include(a_string_matching(/UNCLASSIFIED.*newbie\.yml/))
      end
    end

    it "(b) a dead entry — named workflow gone → error" do
      with_workflows("req.yml" => required_wf("Fixture passed")) do |root| # flip.yml absent
        errors = described_class.audit(root:, perimeter:)[:errors]
        expect(errors).to include(a_string_matching(/dead PERIMETER entry `flip\.yml`.*no such workflow/))
      end
    end

    it "(b) a dead entry — workflow present but no longer PR-triggered → error" do
      push_only = "on:\n  push:\n    branches: [main]\njobs:\n  x:\n    name: x\n"
      with_workflows("req.yml" => required_wf("Fixture passed"),
                     "flip.yml" => push_only) do |root|
        errors = described_class.audit(root:, perimeter:)[:errors]
        expect(errors).to include(a_string_matching(/dead PERIMETER entry `flip\.yml`.*no longer pull_request/))
      end
    end

    it "(c) a :required workflow missing its always() aggregate → error" do
      with_workflows("req.yml" => pr_job, "flip.yml" => pr_job) do |root| # req has no aggregate
        errors = described_class.audit(root:, perimeter:)[:errors]
        expect(errors).to include(a_string_matching(/:required `req\.yml` has NO `if: always\(\)` aggregate/))
      end
    end

    it "a clean fixture perimeter passes with only the flip advisory" do
      with_workflows("req.yml" => required_wf("Fixture passed"), "flip.yml" => pr_job) do |root|
        result = described_class.audit(root:, perimeter:)
        expect(result[:errors]).to be_empty
        expect(result[:advisories]).to include(a_string_matching(/`flip\.yml`.*FLIP\.1/))
      end
    end
  end
end
