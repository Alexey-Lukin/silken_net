# frozen_string_literal: true

require "json"
require "open3"
require "shellwords"

# = =====================================================================
# 🛠 GithubBootstrap — IaC for GitHub Projects V2 + Milestones
# = =====================================================================
#
# Source SSOT: docs/00_05_GitHub_Projects_and_IaC_Automation.md §1.1 + §6.
# Tracker entry: docs/00_07_Action_Plan_Tracker.md → OPS.6.
#
# The `gh` CLI does not yet support `gh project field create` for all
# field types we need (especially single-select with many options), so
# we go through the GraphQL API directly. This module wraps:
#
#   * Project V2 field creation (idempotent — skips fields that already
#     exist, matched by name).
#   * Repository milestone creation (idempotent — REST API returns 422
#     "already_exists" which we treat as success).
#
# Both `bin/setup_github_project.sh` and `bin/bootstrap_github.sh` shell
# out to this module so tests can mock the `gh` executor.
#
# The single source of truth for field schemas lives here in `FIELDS`;
# update docs/00_05 §1.1 in lockstep when adding a field.
# = =====================================================================
module GithubBootstrap
  module_function

  # Field schema — order matters for stable diffs against existing
  # Projects V2 boards.
  # TRL caps at 9 (NASA / ISO 16290 — technology readiness only).
  TRL_OPTIONS = (1..9).map { |n| "TRL:#{n}" }.freeze

  # Beyond TRL 9 is NOT "TRL 10-12" (non-standard). Planetary-intelligence R&D
  # is tracked as a separate dimension: SRL (System Readiness — emergence,
  # self-evolution, cross-biome, AI-security) staged Concept→Pilot→Deployed,
  # and MRL (Manufacturing Readiness, 8-10 — 5-SKU mass production).
  # See 00_02 §1 / 00_08 §1.
  READINESS_HORIZON_OPTIONS = %w[
    SRL:Concept SRL:Pilot SRL:Deployed MRL:8 MRL:9 MRL:10
  ].freeze

  AGENT_OPTIONS = [
    "Architect", "AI Agent", "Lab (ChNU)", "Factory", "nTop Expert"
  ].freeze

  # Swimlane names — mirror the closed nine of .github/labels.yml (`module:NN-slug`,
  # docs/00_05 §4.4). The old `"%02d: Module"` placeholder shipped nine
  # indistinguishable lanes, which defeats the field's stated purpose ("Формує
  # Swimlanes", §1.1) and made labels.yml's `# Module (matches Project V2 Module
  # field)` untrue.
  MODULE_OPTIONS = [
    "00: Codex", "01: Anchor", "02: Capsule", "03: Firmware", "04: Server Core",
    "05: Ledger", "06: Matrix", "07: NaaS", "08: Academic"
  ].freeze

  APPETITE_OPTIONS = [ "Small Batch", "Big Bet" ].freeze

  CLUSTER_OPTIONS = [
    "A — Hardware/EBFC",
    "B — Verification/Math",
    "C — Scaling/Cloud",
    "D — Compliance/Legal"
  ].freeze
  # NB: no "Cross-cluster" option — docs/00_05 §1.1 retired it as a resting
  # state of the FIELD (exactly one primary cluster = accountability); the
  # transitional case is the `cluster:cross-cluster` LABEL, which the
  # auto-labeler writes and the Betting Table must resolve. A single-select
  # with no auto-writer can only ever be a resting state, so an empty field
  # (= "not triaged", filterable) is the honest transitional value here.

  SHAPE_UP_STAGE_OPTIONS = [
    "Shaping", "Bet (active)", "Building",
    "Hill (uphill)", "Hill (downhill)", "Park", "Drop", "Done"
  ].freeze

  # Cycle / semester are time-bounded; we seed today's + next two so the
  # board has somewhere to drop newly created tickets. Operators add more
  # via the UI for long-running planning.
  CYCLE_OPTIONS = %w[Cycle\ 2026.Q2 Cycle\ 2026.Q3 Cycle\ 2026.Q4 Cycle\ 2027.Q1].freeze
  SEMESTER_OPTIONS = [
    "Spring 2025-2026", "Fall 2026-2027",
    "Spring 2026-2027", "Fall 2027-2028"
  ].freeze

  FIELDS = [
    { name: "Current TRL",       type: :single_select, options: TRL_OPTIONS },
    { name: "Target TRL",        type: :single_select, options: TRL_OPTIONS },
    { name: "Readiness Horizon", type: :single_select, options: READINESS_HORIZON_OPTIONS },
    { name: "Assigned Agent",    type: :single_select, options: AGENT_OPTIONS },
    { name: "Module",            type: :single_select, options: MODULE_OPTIONS },
    { name: "Appetite",          type: :single_select, options: APPETITE_OPTIONS },
    { name: "SSOT Link",         type: :text          },
    { name: "R&D Cluster",       type: :single_select, options: CLUSTER_OPTIONS },
    { name: "Shape Up Stage",    type: :single_select, options: SHAPE_UP_STAGE_OPTIONS },
    { name: "Cycle",             type: :single_select, options: CYCLE_OPTIONS },
    { name: "Academic Semester", type: :single_select, options: SEMESTER_OPTIONS }
  ].freeze

  # = -------------------------------------------------------------------
  # Public API
  # = -------------------------------------------------------------------

  # Ensure every field in FIELDS exists on the target Project V2 board.
  # Returns an array of `:created` / `:exists` actions per field, in the
  # same order as FIELDS, so callers can log a stable summary.
  #
  # @param owner          [String] GitHub user/org owning the project
  # @param project_number [Integer] Project V2 number (`gh project list`)
  # @param executor       [#call] Lambda receiving `[*argv]` and returning
  #                       [stdout, status_code]. Defaults to shelling out
  #                       to the real `gh` CLI; tests inject a stub.
  def sync_project_fields(owner:, project_number:, executor: method(:default_executor))
    project = fetch_project(owner: owner, project_number: project_number, executor: executor)
    existing = project.fetch("fields").fetch("nodes").map { |f| f["name"] }.to_set

    FIELDS.map do |field|
      if existing.include?(field[:name])
        [ field[:name], :exists ]
      else
        create_field!(project_id: project["id"], field: field, executor: executor)
        [ field[:name], :created ]
      end
    end
  end

  # Create a milestone on the repo if it does not exist (matched by
  # title). REST endpoint per `docs/00_05 §6` step 3. Returns
  # `:created` / `:exists`.
  def ensure_milestone(owner:, repo:, title:, description: nil, executor: method(:default_executor))
    listing, status = executor.call([
      "api", "repos/#{owner}/#{repo}/milestones?state=open"
    ])
    raise_for_status(status, "list milestones for #{owner}/#{repo}")
    parsed = JSON.parse(listing)
    return :exists if parsed.any? { |m| m["title"] == title }

    args = [
      "api", "repos/#{owner}/#{repo}/milestones",
      "-f", "title=#{title}"
    ]
    args.push("-f", "description=#{description}") if description
    _, status = executor.call(args)
    raise_for_status(status, "create milestone #{title.inspect}")
    :created
  end

  # Whole orchestration as described in docs/00_05 §6.
  # Returns a Hash summarising actions for logger / test assertions.
  def bootstrap(owner:, repo:, project_number:, cycle_title:, cycle_description: nil,
                executor: method(:default_executor))
    {
      fields:    sync_project_fields(owner: owner, project_number: project_number, executor: executor),
      milestone: ensure_milestone(owner: owner, repo: repo, title: cycle_title,
                                  description: cycle_description, executor: executor)
    }
  end

  # = -------------------------------------------------------------------
  # GraphQL plumbing
  # = -------------------------------------------------------------------

  PROJECT_QUERY = <<~GQL
    query($owner: String!, $number: Int!) {
      user(login: $owner) {
        projectV2(number: $number) {
          id
          title
          fields(first: 50) {
            nodes {
              ... on ProjectV2FieldCommon { id name dataType }
            }
          }
        }
      }
    }
  GQL

  CREATE_TEXT_FIELD = <<~GQL
    mutation($projectId: ID!, $name: String!) {
      createProjectV2Field(input: { projectId: $projectId, dataType: TEXT, name: $name }) {
        projectV2Field { ... on ProjectV2FieldCommon { id name } }
      }
    }
  GQL

  CREATE_SINGLE_SELECT_FIELD = <<~GQL
    mutation($projectId: ID!, $name: String!, $options: [ProjectV2SingleSelectFieldOptionInput!]!) {
      createProjectV2Field(input: {
        projectId: $projectId, dataType: SINGLE_SELECT, name: $name,
        singleSelectOptions: $options
      }) {
        projectV2Field { ... on ProjectV2FieldCommon { id name } }
      }
    }
  GQL

  def fetch_project(owner:, project_number:, executor:)
    stdout, status = executor.call([
      "api", "graphql",
      "-f", "query=#{PROJECT_QUERY}",
      "-F", "owner=#{owner}",
      "-F", "number=#{project_number}"
    ])
    raise_for_status(status, "fetch project #{owner}/##{project_number}")
    payload = JSON.parse(stdout)
    project = payload.dig("data", "user", "projectV2")
    raise Error, "Project #{owner}/##{project_number} not found" if project.nil?
    project
  end

  def create_field!(project_id:, field:, executor:)
    case field[:type]
    when :text          then create_text_field(project_id, field[:name], executor: executor)
    when :single_select then create_single_select(project_id, field[:name], field[:options], executor: executor)
    else
      raise Error, "Unsupported field type #{field[:type].inspect}"
    end
  end

  def create_text_field(project_id, name, executor:)
    args = [
      "api", "graphql",
      "-f", "query=#{CREATE_TEXT_FIELD}",
      "-F", "projectId=#{project_id}",
      "-F", "name=#{name}"
    ]
    _, status = executor.call(args)
    raise_for_status(status, "create TEXT field #{name.inspect}")
  end

  def create_single_select(project_id, name, options, executor:)
    options_payload = options.map { |opt| { name: opt, color: "GRAY", description: "" } }
    args = [
      "api", "graphql",
      "-f", "query=#{CREATE_SINGLE_SELECT_FIELD}",
      "-F", "projectId=#{project_id}",
      "-F", "name=#{name}",
      "--raw-field", "options=#{JSON.generate(options_payload)}"
    ]
    _, status = executor.call(args)
    raise_for_status(status, "create SINGLE_SELECT field #{name.inspect}")
  end

  # = -------------------------------------------------------------------
  # Executor — `gh` CLI by default; tests pass a stub lambda.
  # = -------------------------------------------------------------------

  def default_executor(argv)
    stdout, _stderr, status = Open3.capture3("gh", *argv)
    [ stdout, status.exitstatus ]
  end

  def raise_for_status(status, context)
    return if status.zero?
    raise Error, "gh CLI failed (status=#{status}) while trying to #{context}"
  end

  class Error < StandardError; end
end
