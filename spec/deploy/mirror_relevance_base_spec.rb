# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"
require "yaml"

# [INF.17] The GHCR mirror's change detector must diff against what the registry HOLDS, never
# against a single commit. Measured 2026-09-03: `gh api commits/${HEAD_SHA}` listed the files of
# the push's LAST commit only, so the commit canopy went live on (6dd6f6e) never got its `sha-`
# tag and the anchor daemon pin had nothing to point at — the same axis deploy.yml closed on
# 2026-09-02 [INF.9]. The base is now the head SHA of the newest run whose `Build & Push to GHCR`
# job succeeded, compared through the compare API.
#
# 🔒 Declared ceiling: this reads the step's SCRIPT — it pins the shape of the question
# (base = last successful mirror, range diff, no single-commit read), not that GitHub answers
# it correctly; that half is measured by the next multi-commit push.
RSpec.describe "GHCR mirror relevance base [INF.17]" do # rubocop:disable RSpec/DescribeClass
  let(:decide) do
    workflow = YAML.safe_load(File.read(Rails.root.join(".github/workflows/mirror-ghcr.yml")), aliases: true)
    workflow.dig("jobs", "changes", "steps").find { |step| step["id"] == "decide" }.fetch("run")
  end

  it "diffs the push RANGE against the last SUCCESSFUL mirror, never a single commit" do
    aggregate_failures do
      expect(decide).to include('select(.name == "Build & Push to GHCR" and .conclusion == "success")')
      expect(decide).to include("compare/${BASE}...${HEAD_SHA}")
      # the CALL form, not the word — the step's own comment names the retired form as history
      expect(decide).not_to match(%r{gh api "[^"]*/commits/\$\{HEAD_SHA\}"})
    end
  end

  it "builds on every ambiguity (no base · API failure · capped file list)" do
    aggregate_failures do
      expect(decide).to include("No previous successful GHCR mirror found")
      expect(decide).to include("Could not diff")
      expect(decide).to include("-ge 300")
    end
  end

  it "reads a real decide script (non-vacuity)" do
    expect(decide.lines.size).to be > 25
  end
end
