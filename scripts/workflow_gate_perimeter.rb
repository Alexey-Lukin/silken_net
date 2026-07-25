#!/usr/bin/env ruby
# frozen_string_literal: true

# Gate-perimeter meta-guard (OPS.14).
#
# `main`'s branch protection requires all seven deterministic PR-gates —
# `CI passed` (ci-ok), `Docs passed` (docs-ok), `Solidity passed` (money-path
# SCC/SFC/Governor), and the `CAD passed` / `ML passed` / `In-silico passed` /
# `IaC passed` smokes. Only `ssot_guard.yml` stays advisory-by-design (path-gated
# red-X informs, does not block). One entry is flip-pending: `dco.yml` (UNI.20) —
# its aggregate is in place, the branch-protection flip is a founder action.
# Nothing watched the gate PERIMETER itself: a new deterministic PR-gate can be
# born outside the required
# set and nobody notices — exactly how the money-path Solidity audit stayed
# merge-advisory while canon claimed "all gating". Sibling class of DOC-T.44
# ("a gate outside the registry rots one-way") — the class bites, no guard
# existed. This is that guard.
#
# The PERIMETER hash below is the curated SSOT: it classifies EVERY
# pull_request-triggered `.github/workflows/*.yml` into one of three buckets —
#
#   :required           → merge-blocking via an `if: always()` aggregate job
#                         whose `name:` is the branch-protection context
#                         (e.g. ci.yml→"CI passed", solidity_audit.yml→"Solidity passed").
#   :advisory_by_design → deliberately NOT merge-blocking, with a ratified
#                         reason (today: ssot_guard.yml — path-gated red-X
#                         informs, does not block; 06_07 §2).
#   :flip_pending       → SHOULD become required, tracked in 00_07. The value is
#                         the tracking ID. Shrinks to 0 as the aggregates land +
#                         branch protection is updated, at which point the entry
#                         moves :flip_pending → :required.
#
# HARD checks (exit 1):
#   (a) every pull_request-triggered workflow is classified (a NEW one → RED
#       "classify it": a merge-gate must not be born outside the perimeter);
#   (b) no dead PERIMETER entry (named workflow gone / no longer PR-triggered);
#   (c) every :required workflow actually HAS its `if: always()` aggregate job
#       (parsed — a job whose resolved name == the label AND whose `if` carries
#       always()).
# ADVISORY (report, never exit 1): the :flip_pending list — a migration tracker.
#
# OPTIONAL --live: best-effort `gh api …/branches/main/protection/
# required_status_checks`; asserts each :required label ∈ contexts. Skips
# gracefully if `gh` is unauthenticated / errors (this path is for local/manual
# runs, NOT CI — CI's default token can't read protection). A successful query
# that is MISSING a :required label is real drift → exit 1.
#
# Pure Ruby (yaml/json/open3 stdlib, no Rails). Sibling tripwire-style curated
# map, like guard_registry_sync's CANON_CODE_GATES_OUTSIDE_DOCS: a dead entry
# and an unclassified newcomer both go RED, so the perimeter cannot rot in
# either direction. Run: ruby scripts/workflow_gate_perimeter.rb [--live]
# Exit 0 = perimeter sound; exit 1 = a HARD violation. Method/why → 06_07 §2.

require "yaml"
require "json"
require "open3"

module WorkflowGatePerimeter
  ROOT   = File.expand_path("..", __dir__)
  WF_DIR = ".github/workflows"

  # Curated SSOT — classify EVERY pull_request-triggered workflow. `[class, meta]`
  # where meta = the branch-protection check name (:required), the ratified reason
  # (:advisory_by_design), or the 00_07 tracking ID (:flip_pending).
  PERIMETER = {
    "ci.yml"              => [ :required,           "CI passed" ],
    "docs.yml"            => [ :required,           "Docs passed" ],
    "ssot_guard.yml"      => [ :advisory_by_design, "path-gated red-X informs, not blocks — 06_07 §2" ],
    "solidity_audit.yml"  => [ :required,           "Solidity passed" ],
    "cad_smoke.yml"       => [ :required,           "CAD passed" ],
    "ml_smoke.yml"        => [ :required,           "ML passed" ],
    "in_silico_smoke.yml" => [ :required,           "In-silico passed" ],
    "iac_scan.yml"        => [ :required,           "IaC passed" ],
    # DCO sign-off on inbound PRs. :flip_pending until 2026-07-25, when the founder
    # added `DCO passed` to the required set — verified live against the API, not
    # assumed (`gh api …/branches/main/protection/required_status_checks` returns it
    # among 8 contexts). Held at :flip_pending before that on purpose: branch
    # protection is a founder action this repo's CI token cannot perform, and
    # claiming :required early would be exactly the "canon says gating, nothing
    # gates" drift this guard exists to catch.
    "dco.yml"             => [ :required,           "DCO passed" ]
  }.freeze

  CLASSES = %i[required advisory_by_design flip_pending].freeze

  module_function

  # pull_request-trigger detection, robust to the YAML-1.1 bare-`on:`→boolean
  # quirk (`on:` parses to the key `true`, not "on"). Deliberately does NOT count
  # `pull_request_target` (a different, privileged event — labeler.yml — that is
  # an automation, not a merge-gate).
  def pr_triggered?(yaml)
    on = yaml["on"] || yaml[true]
    case on
    when Hash   then on.key?("pull_request")
    when Array  then on.include?("pull_request")
    when String then on == "pull_request"
    else false
    end
  end

  # An `if: always()` aggregate job whose resolved name (`name:` or, absent that,
  # the job id) == the branch-protection label. Both halves load-bearing: the
  # aggregate exists AND it carries the exact context name that branch protection
  # requires. Matches `if: always()` and `if: ${{ always() }}`.
  def always_aggregate?(yaml, label)
    (yaml["jobs"] || {}).any? do |job_id, job|
      next false unless job.is_a?(Hash)

      (job["name"] || job_id).to_s.strip == label &&
        job["if"].to_s.match?(/always\s*\(\s*\)/)
    end
  end

  def workflow_files(root)
    Dir[File.join(root, WF_DIR, "*.yml")].sort
  end

  # Returns { errors:, advisories:, pr_workflows:, classified: }.
  def audit(root: ROOT, perimeter: PERIMETER)
    errors     = []
    advisories = []
    classified = {}

    parsed = {}
    workflow_files(root).each do |path|
      base = File.basename(path)
      begin
        parsed[base] = YAML.safe_load_file(path, aliases: true)
      rescue Psych::Exception => e
        errors << "#{base}: YAML parse failed (#{e.class}: #{e.message.lines.first&.strip})"
      end
    end

    pr_workflows = parsed.select { |_b, y| y.is_a?(Hash) && pr_triggered?(y) }.keys.sort

    # (a) every PR-triggered workflow is classified.
    (pr_workflows - perimeter.keys).each do |base|
      errors << "UNCLASSIFIED pull_request-gate `#{base}` — add it to PERIMETER " \
                "(:required / :advisory_by_design / :flip_pending). A merge-gate " \
                "must not be born outside the perimeter."
    end

    # (b) no dead PERIMETER entry, and per-entry classification + (c).
    perimeter.each do |base, (cls, meta)|
      classified[base] = [ cls, meta ]

      unless CLASSES.include?(cls)
        errors << "PERIMETER `#{base}`: unknown class #{cls.inspect} " \
                  "(∈ #{CLASSES.inspect})"
        next
      end

      if !parsed.key?(base)
        errors << "dead PERIMETER entry `#{base}` — no such workflow on disk (drop it)."
        next
      elsif !pr_workflows.include?(base)
        errors << "dead PERIMETER entry `#{base}` — no longer pull_request-triggered " \
                  "(drop or re-scope it)."
        next
      end

      case cls
      when :required
        unless always_aggregate?(parsed[base], meta)
          errors << ":required `#{base}` has NO `if: always()` aggregate job named " \
                    "#{meta.inspect} — the merge-blocking check must exist as an " \
                    "aggregate (branch protection requires that exact context name)."
        end
      when :flip_pending
        advisories << "`#{base}` → SHOULD be required (→ #{meta}) — today job-gating " \
                      "but merge-ADVISORY."
      end
    end

    { errors:, advisories:, pr_workflows:, classified: }
  end

  # Best-effort branch-protection cross-check. Returns { notes:, violations: }.
  # Graceful skip when `gh` errors (unauth / no protection / offline); a
  # SUCCESSFUL query missing a :required label is genuine drift → violation.
  def live_check(root: ROOT, perimeter: PERIMETER)
    required = perimeter.select { |_b, (c, _m)| c == :required }.map { |_b, (_c, m)| m }
    out, status = begin
      Open3.capture2e("gh", "api",
                      "repos/:owner/:repo/branches/main/protection/required_status_checks")
    rescue Errno::ENOENT
      return { notes: [ "--live: `gh` CLI not found — skipped (local/manual path)." ], violations: [] }
    end

    unless status.success?
      return { notes: [ "--live: gh api unavailable/unauthenticated — skipped " \
                        "(#{out.lines.first&.strip}). This path is for local/manual runs, not CI." ],
               violations: [] }
    end

    data = begin
      JSON.parse(out)
    rescue JSON::ParserError
      {}
    end
    contexts = Array(data["contexts"]) |
               Array(data["checks"]).filter_map { |c| c.is_a?(Hash) ? c["context"] : nil }

    notes = []
    violations = []
    required.each do |label|
      if contexts.include?(label)
        notes << "--live ✓ `#{label}` ∈ branch-protection required contexts"
      else
        violations << "--live ✗ `#{label}` is PERIMETER :required but NOT in " \
                      "branch-protection required_status_checks #{contexts.inspect} — " \
                      "the gate is not actually enforced."
      end
    end
    { notes:, violations: }
  end
end

if __FILE__ == $PROGRAM_NAME
  live   = ARGV.include?("--live")
  result = WorkflowGatePerimeter.audit

  # Classified perimeter (always printed — the report either way).
  puts "workflow_gate_perimeter — gate PERIMETER (#{result[:pr_workflows].size} " \
       "pull_request-triggered workflows):"
  WorkflowGatePerimeter::PERIMETER.each do |base, (cls, meta)|
    tag = { required: "🔒 required", advisory_by_design: "◽ advisory-by-design",
            flip_pending: "⏫ flip-pending" }[cls]
    puts "  · #{base.ljust(21)} #{tag.ljust(22)} #{meta}"
  end

  unless result[:advisories].empty?
    puts "\nflip_pending — SHOULD be required (migration tracker, shrinks to 0):"
    result[:advisories].sort.each { |a| puts "  · #{a}" }
  end

  live_violations = []
  if live
    lr = WorkflowGatePerimeter.live_check
    puts "\nbranch-protection cross-check (--live):"
    (lr[:notes] + lr[:violations]).each { |n| puts "  · #{n}" }
    live_violations = lr[:violations]
  end

  if result[:errors].empty? && live_violations.empty?
    puts "\nworkflow_gate_perimeter ✓ — perimeter sound: every PR-gate classified, " \
         "no dead entry, every :required aggregate present" \
         "#{live ? " (+ live branch-protection verified)" : ""}."
    exit 0
  else
    warn "\nworkflow_gate_perimeter ✗ — gate-perimeter drift (OPS.14):"
    (result[:errors] + live_violations).each { |e| warn "  · #{e}" }
    exit 1
  end
end
