# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"
require "yaml"

# [INF.9] The canopy deploy-relevance detector must diff against what canopy is RUNNING,
# never against a single commit. Measured 2026-09-02: `gh api commits/${HEAD_SHA}` listed the
# files of the push's LAST commit only, so a four-commit push ending in a docs commit reported
# "No deploy-relevant files changed" and skipped a deploy that carried a secrets-parser fix —
# `Deploy · Canopy` green, nothing deployed, and no gate saw it because the skip is the
# workflow's own happy path. The base is now the head SHA of the newest run whose
# `Kamal Deploy (Canopy)` job succeeded, compared through the compare API.
#
# 🔒 Declared ceiling: this reads the step's SCRIPT — it pins the shape of the question
# (base = last successful deploy, range diff, no single-commit read), not that GitHub answers
# it correctly; that half is measured by the next multi-commit push.
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
end
