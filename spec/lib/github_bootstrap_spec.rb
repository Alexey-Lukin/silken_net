# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"
require "github_bootstrap"

RSpec.describe GithubBootstrap do
  let(:owner) { "TestOrg" }
  let(:project_number) { 7 }
  let(:project_id) { "PVT_TEST_ID" }
  let(:repo) { "sandbox-repo" }

  # Stub executor — captures every call as `{ argv:, stdout:, status: }`
  # and replays the canned response queue in order. Tests pre-stack the
  # responses they expect so the order serves as the assertion.
  let(:invocations) { [] }
  let(:responses) { [] }
  let(:executor) do
    lambda do |argv|
      response = responses.shift || [ "", 0 ]
      invocations << { argv: argv, response: response }
      response
    end
  end

  describe ".sync_project_fields" do
    let(:base_project_payload) do
      {
        "data" => {
          "user" => {
            "projectV2" => { "id" => project_id, "title" => "T", "fields" => { "nodes" => existing_fields } }
          }
        }
      }
    end

    context "with no existing fields" do
      let(:existing_fields) { [] }

      before do
        responses << [ JSON.generate(base_project_payload), 0 ] # initial fetch
        described_class::FIELDS.size.times { responses << [ "{}", 0 ] }
      end

      it "creates every field in FIELDS" do
        result = described_class.sync_project_fields(
          owner: owner, project_number: project_number, executor: executor
        )
        expect(result.size).to eq(described_class::FIELDS.size)
        expect(result.map(&:last)).to all(eq(:created))
      end

      it "issues one fetch + one mutation per field" do
        described_class.sync_project_fields(
          owner: owner, project_number: project_number, executor: executor
        )
        expect(invocations.size).to eq(1 + described_class::FIELDS.size)
      end

      it "uses createProjectV2Field with SINGLE_SELECT for selectable fields" do
        described_class.sync_project_fields(
          owner: owner, project_number: project_number, executor: executor
        )
        single_select_calls = invocations.drop(1).select { |i| i[:argv].join(" ").include?("SINGLE_SELECT") }
        # FIELDS contains 10 single-select definitions + 1 TEXT field.
        expect(single_select_calls.size).to eq(described_class::FIELDS.count { |f| f[:type] == :single_select })
      end

      it "uses createProjectV2Field with TEXT for the SSOT Link field" do
        described_class.sync_project_fields(
          owner: owner, project_number: project_number, executor: executor
        )
        text_call = invocations.drop(1).find { |i| i[:argv].join(" ").include?("dataType: TEXT") }
        expect(text_call).not_to be_nil
        # The TEXT call should be the SSOT Link field (the only TEXT field).
        expect(text_call[:argv].join(" ")).to include("SSOT Link")
      end
    end

    context "when some fields already exist (idempotency)" do
      let(:existing_fields) do
        [
          { "id" => "F1", "name" => "Current TRL", "dataType" => "SINGLE_SELECT" },
          { "id" => "F2", "name" => "Module",      "dataType" => "SINGLE_SELECT" }
        ]
      end

      before do
        responses << [ JSON.generate(base_project_payload), 0 ]
        (described_class::FIELDS.size - 2).times { responses << [ "{}", 0 ] }
      end

      it "skips existing fields and reports :exists" do
        result = described_class.sync_project_fields(
          owner: owner, project_number: project_number, executor: executor
        )
        statuses = result.to_h
        expect(statuses["Current TRL"]).to eq(:exists)
        expect(statuses["Module"]).to eq(:exists)
        expect(statuses["Target TRL"]).to eq(:created)
      end

      it "issues 1 fetch + (FIELDS - 2) mutations, not 1 + FIELDS" do
        described_class.sync_project_fields(
          owner: owner, project_number: project_number, executor: executor
        )
        expect(invocations.size).to eq(1 + described_class::FIELDS.size - 2)
      end
    end

    context "when the project does not exist" do
      before do
        responses << [
          JSON.generate({ "data" => { "user" => { "projectV2" => nil } } }), 0
        ]
      end

      it "raises a descriptive error" do
        expect {
          described_class.sync_project_fields(
            owner: owner, project_number: project_number, executor: executor
          )
        }.to raise_error(described_class::Error, /not found/)
      end
    end

    context "when gh CLI exits non-zero" do
      before { responses << [ "", 1 ] }

      it "raises with the failed step in the message" do
        expect {
          described_class.sync_project_fields(
            owner: owner, project_number: project_number, executor: executor
          )
        }.to raise_error(described_class::Error, /gh CLI failed/)
      end
    end
  end

  describe ".ensure_milestone" do
    context "when the milestone does not exist" do
      before do
        responses << [ JSON.generate([ { "title" => "Cycle 2025.Q1" } ]), 0 ] # list
        responses << [ "{}", 0 ]                                              # create
      end

      it "creates the milestone via the REST API" do
        result = described_class.ensure_milestone(
          owner: owner, repo: repo, title: "Cycle 2026.Q3", executor: executor
        )
        expect(result).to eq(:created)
        create_call = invocations.last
        expect(create_call[:argv]).to include("api", "repos/#{owner}/#{repo}/milestones",
                                              "-f", "title=Cycle 2026.Q3")
      end

      it "forwards the description when supplied" do
        described_class.ensure_milestone(
          owner: owner, repo: repo, title: "Cycle 2026.Q3",
          description: "First betting cycle", executor: executor
        )
        expect(invocations.last[:argv]).to include("-f", "description=First betting cycle")
      end
    end

    context "when the milestone already exists (by title)" do
      before do
        responses << [ JSON.generate([ { "title" => "Cycle 2026.Q3" } ]), 0 ]
      end

      it "returns :exists and does not call POST" do
        result = described_class.ensure_milestone(
          owner: owner, repo: repo, title: "Cycle 2026.Q3", executor: executor
        )
        expect(result).to eq(:exists)
        expect(invocations.size).to eq(1) # only the list call
      end
    end
  end

  describe ".bootstrap" do
    let(:existing_fields) { [] }

    before do
      project_payload = {
        "data" => { "user" => { "projectV2" => {
          "id" => project_id, "title" => "T",
          "fields" => { "nodes" => existing_fields }
        } } }
      }
      responses << [ JSON.generate(project_payload), 0 ]
      described_class::FIELDS.size.times { responses << [ "{}", 0 ] }
      responses << [ JSON.generate([]), 0 ] # list milestones (empty)
      responses << [ "{}", 0 ]              # create milestone
    end

    it "returns a summary of both phases" do
      result = described_class.bootstrap(
        owner: owner, repo: repo, project_number: project_number,
        cycle_title: "Cycle 2026.Q3", executor: executor
      )
      expect(result[:fields].size).to eq(described_class::FIELDS.size)
      expect(result[:milestone]).to eq(:created)
    end
  end

  describe "field schema invariants (docs/00_07 SSOT)" do
    it "caps TRL at 1–9 (NASA/ISO 16290), per docs/00_04 §1" do
      expect(described_class::TRL_OPTIONS.size).to eq(9)
      expect(described_class::TRL_OPTIONS.first).to eq("TRL:1")
      expect(described_class::TRL_OPTIONS.last).to eq("TRL:9")
    end

    it "tracks beyond-TRL-9 as SRL/MRL Readiness Horizon (docs/00_04 §1 + 00_06 §7)" do
      expect(described_class::READINESS_HORIZON_OPTIONS).to include("SRL:Concept", "SRL:Pilot", "SRL:Deployed")
      expect(described_class::READINESS_HORIZON_OPTIONS).to include("MRL:8", "MRL:10")
      expect(described_class::READINESS_HORIZON_OPTIONS).not_to include("TRL:10", "TRL:11", "TRL:12")
    end

    # Reads the canon instead of hand-copying it: the previous version asserted
    # `size == 5` + `include("Cross-cluster")` and so LOCKED a value 00_05 §1.1
    # had retired — a green CI on cancelled canon (the cem_canon_sync failure
    # mode: "the golden test locks the wrong number").
    it "lists exactly the primary R&D clusters that 00_05 §1.1 declares" do
      row = File.read(Rails.root.join("docs/00_05_GitHub_Projects_and_IaC_Automation.md"))
                .lines.find { |l| l.include?("**R&D Cluster**") }
      expect(row).to be_present, "00_05 §1.1 has no R&D Cluster row — canon moved?"

      canon = row.scan(/`([A-D] — [^`]+)`/).flatten
      expect(canon.size).to eq(4), "expected 4 primary clusters in canon, got #{canon.inspect}"
      expect(described_class::CLUSTER_OPTIONS).to match_array(canon)
      expect(described_class::CLUSTER_OPTIONS).not_to include("Cross-cluster")
    end

    it "covers the eight Shape Up stages from 00_07 §1.1" do
      expect(described_class::SHAPE_UP_STAGE_OPTIONS).to contain_exactly("Shaping", "Bet (active)", "Building", "Hill (uphill)", "Hill (downhill)", "Park", "Drop", "Done")
    end

    it "exposes ten single-select fields + one TEXT field (SSOT Link)" do
      single = described_class::FIELDS.count { |f| f[:type] == :single_select }
      text   = described_class::FIELDS.count { |f| f[:type] == :text }
      expect(single).to eq(10)
      expect(text).to eq(1)
    end
  end

  describe ".create_field! with an unsupported type" do
    it "raises a GithubBootstrap::Error" do
      expect {
        described_class.create_field!(project_id: "P_1", field: { type: :bogus, name: "X" }, executor: ->(_argv) { [ "{}", 0 ] })
      }.to raise_error(GithubBootstrap::Error, /Unsupported field type/)
    end
  end
end
