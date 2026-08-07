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

  # An aggregate that DEPENDS on the `changes` path-filter. `assert: true` wires the
  # OPS.23 step that keys a failure on the filter's own result; `false` leaves only
  # the failure-only guard that reads a skipped filter as a legal path-skip.
  def filtered_wf(label, assert:)
    cond = assert ? "needs.changes.result != 'success'" : "contains(needs.*.result, 'failure')"
    <<~YAML
      on:
        pull_request:
      jobs:
        changes:
          runs-on: ubuntu-latest
        agg:
          name: #{label}
          if: ${{ always() }}
          needs: [changes]
          runs-on: ubuntu-latest
          steps:
            - if: #{cond}
              run: exit 1
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

  # [OPS.23] The aggregate existing is not the same as the aggregate being able to
  # tell. `changes` carries no `if:`, so `success` is its only legal result — while
  # the jobs it gates may legally be `skipped`. Both halves of the predicate are
  # pinned separately: a condition keyed on the filter, AND a step that actually fails.
  describe ".filter_result_asserted?" do
    it "accepts an aggregate whose failing step keys on the filter's own result" do
      yaml = YAML.safe_load(filtered_wf("X passed", assert: true))
      expect(described_class.filter_result_asserted?(yaml, "X passed")).to be(true)
    end

    it "rejects a failure-only guard — a SKIPPED filter reads there as a legal path-skip" do
      yaml = YAML.safe_load(filtered_wf("X passed", assert: false))
      expect(described_class.filter_result_asserted?(yaml, "X passed")).to be(false)
    end

    it "requires the step to actually FAIL, not merely to mention the filter" do
      no_exit = YAML.safe_load(<<~YAML)
        jobs:
          agg:
            name: X passed
            needs: [changes]
            steps:
              - if: needs.changes.result != 'success'
                run: echo "noted"
      YAML
      expect(described_class.filter_result_asserted?(no_exit, "X passed")).to be(false)
    end

    it "owes nothing when the aggregate does not depend on the filter (dco.yml shape)" do
      no_filter = YAML.safe_load("jobs:\n  agg:\n    name: X passed\n    steps: []")
      expect(described_class.filter_result_asserted?(no_filter, "X passed")).to be(true)
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

    # A lantern on check (f)'s own subject: it only inspects aggregates that depend
    # on the filter, so were those `needs:` to disappear, (f) would pass over an
    # EMPTY set and stay green forever. `dco.yml` is the one legitimate exemption.
    it "leaves check (f) a non-empty population to inspect" do
      filtered = WorkflowGatePerimeter::PERIMETER.select { |_b, (c, _)| c == :required }
                                                 .keys.count do |base|
        yaml = YAML.safe_load_file(".github/workflows/#{base}", aliases: true)
        job  = described_class.aggregate_job(yaml, WorkflowGatePerimeter::PERIMETER[base][1])
        Array(job&.dig("needs")).include?(WorkflowGatePerimeter::FILTER_JOB)
      end
      expect(filtered).to be > 1
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

    it "(f) a :required aggregate that depends on the filter but never asserts it → error" do
      with_workflows("req.yml" => filtered_wf("Fixture passed", assert: false),
                     "flip.yml" => pr_job) do |root|
        errors = described_class.audit(root:, perimeter:)[:errors]
        expect(errors).to include(a_string_matching(/`req\.yml`.*never asserts its RESULT/))
      end
    end

    it "(f) the same aggregate WITH the filter assertion is clean" do
      with_workflows("req.yml" => filtered_wf("Fixture passed", assert: true),
                     "flip.yml" => pr_job) do |root|
        expect(described_class.audit(root:, perimeter:)[:errors]).to be_empty
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
