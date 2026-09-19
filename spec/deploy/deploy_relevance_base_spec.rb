# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"
require "yaml"
require "open3"
require "tmpdir"

# [INF.9] The canopy deploy-relevance detector must diff against what canopy is RUNNING,
# never against a single commit. Measured 2026-09-02: `gh api commits/${HEAD_SHA}` listed the
# files of the push's LAST commit only, so a four-commit push ending in a docs commit reported
# "No deploy-relevant files changed" and skipped a deploy that carried a secrets-parser fix —
# `Deploy · Canopy` green, nothing deployed, and no gate saw it because the skip is the
# workflow's own happy path. The base is now the head SHA of the newest run whose
# `Kamal Deploy (Canopy)` job succeeded, compared through the compare API.
#
# 🔒 Declared ceiling: the INF.9 examples read the step's SCRIPT — they pin the shape of the
# question (base = last successful deploy, range diff, no single-commit read), not that GitHub
# answers it correctly; that half is measured by the next multi-commit push. The Фаза ∅ block
# below RUNS the script against a fake `gh`, so it proves the branch logic, never the real API.
RSpec.describe "canopy deploy-relevance base [INF.9]" do # rubocop:disable RSpec/DescribeClass
  let(:decide) do
    workflow = YAML.safe_load(File.read(Rails.root.join(".github/workflows/deploy.yml")), aliases: true)
    workflow.dig("jobs", "changes", "steps").find { |step| step["id"] == "decide" }.fetch("run")
  end

  it "diffs the push RANGE against the last SUCCESSFUL canopy deploy, never a single commit" do
    aggregate_failures do
      expect(decide).to include('select(.name == "Kamal Deploy (Canopy)" and .conclusion == "success")')
      expect(decide).to include("compare/${BASE}...${HEAD_SHA}")
      # the CALL form, not the word — the step's own comment names the retired form as history
      expect(decide).not_to match(%r{gh api "[^"]*/commits/\$\{HEAD_SHA\}"})
    end
  end

  it "deploys on every ambiguity (no base · API failure · capped file list)" do
    aggregate_failures do
      expect(decide).to include("No previous successful canopy deploy found")
      expect(decide).to include("Could not diff")
      expect(decide).to include("-ge 300")
    end
  end

  it "reads a real decide script (non-vacuity)" do
    expect(decide.lines.size).to be > 25
  end

  # ⏳ [Фаза ∅ · амана, 2026-09-19] A stopped stack skips the deploy only BEFORE its review date;
  # after it — or with no date — the red must come back. Runs the REAL step with a fake `gh` on
  # PATH (posture from a fixture, every other API call empty ⇒ "no base" ⇒ deploy=true), so a
  # skip that loses its term fails here, not silently on the day the stack should have been re-asked.
  describe "Фаза ∅ posture gate (runs the step)" do
    def run_decide(posture)
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "posture"), posture)
        gh = File.join(dir, "gh")
        File.write(gh, <<~SH)
          #!/usr/bin/env bash
          case "$*" in *contents/terraform/posture.auto.tfvars*) cat "#{dir}/posture" ;; esac
        SH
        File.chmod(0o755, gh)
        out = File.join(dir, "out")
        script = decide.gsub("${{ github.event_name }}", "workflow_run").gsub("${{ github.repository }}", "o/r")
        env = { "PATH" => "#{dir}:#{ENV.fetch('PATH')}", "GITHUB_OUTPUT" => out, "HEAD_SHA" => "abc", "GH_TOKEN" => "x" }
        stdout, status = Open3.capture2e(env, "bash", "-e", "-c", script)
        [ File.read(out), stdout, status ]
      end
    end

    let(:stopped) { %(db_activation_policy   = "NEVER"\ncompute_desired_status = "TERMINATED"\n) }

    it "skips before the review date, deploys (and warns) on or after it, and never skips without one" do
      aggregate_failures do
        skipped, notice, = run_decide(%(#{stopped}duty_cycle_review_by = "2999-12-31"\n))
        expect(skipped).to eq("deploy=false\n")
        expect(notice).to include("Фаза ∅")

        expired, warning, = run_decide(%(#{stopped}duty_cycle_review_by = "2000-01-01"\n))
        expect(expired).to eq("deploy=true\n")
        expect(warning).to include("::warning::")

        expect(run_decide(stopped).first).to eq("deploy=true\n")
        expect(run_decide(%(compute_desired_status = "RUNNING"\n)).first).to eq("deploy=true\n")
      end
    end

    it "reads the SAME variable terraform declares and the posture file sets" do
      aggregate_failures do
        expect(decide).to include("duty_cycle_review_by")
        expect(File.read(Rails.root.join("terraform/variables.tf"))).to include('variable "duty_cycle_review_by"')
        expect(File.read(Rails.root.join("terraform/posture.auto.tfvars"))).to match(/^duty_cycle_review_by\s*=/)
      end
    end
  end
end
