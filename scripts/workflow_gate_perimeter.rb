#!/usr/bin/env ruby
# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Gate-perimeter meta-guard (OPS.14).
#
# `main`'s branch protection requires all nine deterministic PR-gates —
# `CI passed` (ci-ok), `Docs passed` (docs-ok), `Solidity passed` (money-path
# SCC/SFC/Governor), `Subgraph passed`, and the `CAD passed` / `ML passed` /
# `In-silico passed` / `IaC passed` smokes + `DCO passed`. Only `ssot_guard.yml`
# stays advisory-by-design (path-gated red-X informs, does not block).
# 🔴 On the flip-pending bucket, trust only the run's own output, never a prose
# sentence here: this header once claimed the bucket was EMPTY for three days
# while `subgraph.yml` sat in it (2026-08-27 → 08-30) — and check (e), which
# catches prose that MISNAMES a workflow's class, is blind to the shape "the
# bucket is empty" because that shape names no workflow at all. The PERIMETER
# hash below is the SSOT; the live tenant list is what the run prints.
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
#   (f) every :required aggregate that DEPENDS on the `changes` path-filter also
#       asserts that filter's own result (OPS.23). Existence of the aggregate is
#       not enough: `changes` carries no `if:`, so `success` is its only legal
#       result, and a guard asking merely "did anything fail/cancel?" reads a
#       SKIPPED filter as a legal path-skip and goes green having run nothing.
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
    # among the required contexts — the tally is deliberately not written down here,
    # it moves with the perimeter and `PERIMETER` below is what states it). Held at :flip_pending before that on purpose: branch
    # protection is a founder action this repo's CI token cannot perform, and
    # claiming :required early would be exactly the "canon says gating, nothing
    # gates" drift this guard exists to catch.
    "dco.yml"             => [ :required,           "DCO passed" ],
    # [OPS.34] Компіляція субграфа — поверхні, з якої ЗОВНІШНІЙ читач бере нашу
    # емісію. Девʼятий required-контекст (фліп 2026-08-30). Форма несуча, не
    # стилістична: `pull_request:` мусить лишатись ГОЛИМ — path-filtered
    # required-чек блокує чужі PR назавжди («Expected — waiting for status»:
    # воркфлоу без збігу шляхів не СТАРТУЄ, check-run не народжується, і
    # aggregate безсилий за побудовою — він не може відзвітувати з прогону,
    # якого не було). Фільтр тому живе в джобі `changes` (dorny/paths-filter),
    # `build` гейтиться на її вихід, а `Subgraph passed` (if: always()) несе
    # обидва гарди — провал/скасування + власний результат `changes` (перевірка
    # (f)). Та сама форма, що ci.yml/docs.yml; переносити фільтр назад у
    # `on.pull_request.paths` = повернути пастку, яку цей фліп знімав.
    "subgraph.yml"        => [ :required,           "Subgraph passed" ]
  }.freeze

  CLASSES = %i[required advisory_by_design flip_pending].freeze

  # The path-filter job every path-gated workflow here opens with. Named once
  # because check (f) below keys on it.
  FILTER_JOB = "changes"

  # ── (d)+(e) prose-claim consistency [DOC-T.51] ───────────────────────────────
  # The required-gate COUNT settles into a dozen prose homes (canon, PR template,
  # assurance case, skills, this file's own header) and no guard watched it: the
  # only thing that knew the truth was `--live`, which cannot run in CI. These two
  # checks need no token — they compare prose against the PERIMETER hash above,
  # which `--live` independently verifies against the API on a manual run.
  CLAIM_TREES = %w[docs .github .claude scripts].freeze
  CLAIM_EXTS  = %w[.md .yml .yaml .rb].freeze
  # release-please generates CHANGELOG.md from commit subjects — not a claim surface.
  CLAIM_SKIP  = /(^|\/)CHANGELOG\.md$/.freeze

  # The anchor is a COLLOCATION, not a word. `required` and `deterministic` alone
  # are among the commonest words in this canon — anchoring on them made the check
  # ~19% precise (a noisy gate is a disabled gate). It must be `required` + a
  # gate-noun, or an explicit PR/CI-gate compound.
  GATE_ANCHOR = /
      required[\s\-]*(?:status[\s\-]*check\w*|aggregate\w*|чек\w*|контекст\w*|gate\w*|гейт\w*)
    | (?:PR|CI)[\s\-]?(?:гейт\w*|gate\w*)
    | status[\s\-]check\w*
  /xi
  # Spelled-out forms actually used in this corpus (uk declensions + en).
  WORD_NUMS = { "сім" => 7, "семи" => 7, "сьом" => 7, "seven" => 7,
                "вісім" => 8, "восьм" => 8, "вісьм" => 8, "eight" => 8,
                "шість" => 6, "шести" => 6, "six" => 6,
                "дев'ять" => 9, "дев'яти" => 9, "nine" => 9 }.freeze
  PLAUSIBLE = (5..12)
  PROXIMITY = 45 # chars between numeral and gate word for it to read as a claim

  module_function

  # Strip tokens that carry digits but are NOT counts: code spans (`06_07 §2`,
  # `ci.yml`), doc-ids, §-refs, ISO dates, ordinals in parens.
  def scrub_numerals(line)
    line.gsub(/`[^`]*`/, " ")
        .gsub(/\d\d_\d\d/, " ")
        .gsub(/§\s*\d+(?:\.\d+)*/, " ")
        .gsub(/\(\d+\)/, " ")
        .gsub(/\bTRL[\s-]*\d+/i, " ") # "TRL 9" sits next to gate words in the TRL canon
        .gsub(/~?\d+\+/, " ")         # "~150+ питань"
  end

  # (d) Every live prose claim about HOW MANY gates are required must equal the
  #     :required count in PERIMETER.
  # ⚠️ Declared ceiling: a line carrying an ISO date is read as a HISTORICAL
  #    record ("завершено 2026-07-19: усі 7") and skipped — so a stale claim that
  #    happens to carry a date stays invisible. Undated prose = a live claim.
  def count_claim_violations(root: ROOT, perimeter: PERIMETER)
    expected = perimeter.count { |_b, (cls, _m)| cls == :required }
    each_claim_line(root).filter_map do |rel, lineno, line|
      next unless line.match?(GATE_ANCHOR)
      next if line.match?(/\d{4}-\d{2}-\d{2}/) # historical record, see ceiling above

      text    = scrub_numerals(line)
      anchors = text.enum_for(:scan, GATE_ANCHOR).map { Regexp.last_match.begin(0) }
      next if anchors.empty? # the anchor lived inside a scrubbed code span

      # Proximity is what separates a CLAIM from a coincidence: the numeral must
      # sit next to the gate word, not merely on the same line.
      found = text.enum_for(:scan, /(?<![\d.])(\d{1,2})(?![\d.])/)
                  .map { [ Regexp.last_match[1].to_i, Regexp.last_match.begin(0) ] }
      WORD_NUMS.each do |stem, v|
        text.enum_for(:scan, /(?<!\p{L})#{Regexp.escape(stem)}/i)
            .each { found << [ v, Regexp.last_match.begin(0) ] }
      end
      bad = found.select { |n, pos|
        PLAUSIBLE.cover?(n) && n != expected &&
          anchors.any? { |a| (a - pos).abs <= PROXIMITY }
      }.map(&:first).uniq
      next if bad.empty?

      "#{rel}:#{lineno} claims #{bad.join('/')} required gate(s) — PERIMETER has " \
        "#{expected}: #{line.strip[0, 100]}"
    end
  end

  # (e) Prose that names a workflow as flip-pending must agree with its PERIMETER
  #     class. Catches this file's OWN header, which claimed `dco.yml` was
  #     flip-pending four lines under a sentence saying all eight are required.
  def flip_claim_violations(root: ROOT, perimeter: PERIMETER)
    each_claim_line(root).filter_map do |rel, lineno, line|
      next if line.match?(/\d{4}-\d{2}-\d{2}/) # dated = historical record (same ceiling as (d))

      m = line.match(/flip[-\s_]?pending/i)
      next unless m

      # A CLAIM names ONE workflow after the phrase ("flip-pending: <one>.yml").
      # A line listing several is DEFINITIONAL (it enumerates all three classes) —
      # declared ceiling: a stale definitional line stays invisible to this check.
      names = line[m.end(0)..].to_s.scan(/([a-z0-9_]+\.yml)/).flatten.uniq
      next unless names.size == 1

      wf  = names.first
      cls = perimeter[wf]&.first
      next if cls == :flip_pending

      "#{rel}:#{lineno} calls `#{wf}` flip-pending, but PERIMETER classifies it " \
        "#{cls ? ":#{cls}" : "not at all"}: #{line.strip[0, 100]}"
    end
  end

  def each_claim_line(root)
    return enum_for(:each_claim_line, root) unless block_given?

    CLAIM_TREES.each do |tree|
      Dir.glob(File.join(root, tree, "**", "*")).sort.each do |path|
        next unless File.file?(path) && CLAIM_EXTS.include?(File.extname(path))

        rel = path.delete_prefix("#{root}/")
        next if rel.match?(CLAIM_SKIP)

        File.readlines(path, chomp: true).each_with_index do |line, i|
          yield rel, i + 1, line
        end
      end
    end
    Dir.glob(File.join(root, "*.md")).sort.each do |path|
      rel = path.delete_prefix("#{root}/")
      next if rel.match?(CLAIM_SKIP)

      File.readlines(path, chomp: true).each_with_index { |line, i| yield rel, i + 1, line }
    end
  end

  # pull_request-trigger detection, robust to the YAML-1.1 bare-`on:`→boolean
  # quirk (`on:` parses to the key `true`, not "on"). Deliberately does NOT count
  # `pull_request_target` (a different, privileged event that is
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

  # The job whose resolved name (`name:` or, absent that, the job id) == the
  # branch-protection label; nil when absent.
  def aggregate_job(yaml, label)
    (yaml["jobs"] || {}).each do |job_id, job|
      next unless job.is_a?(Hash)
      return job if (job["name"] || job_id).to_s.strip == label
    end
    nil
  end

  # An `if: always()` aggregate job whose resolved name (`name:` or, absent that,
  # the job id) == the branch-protection label. Both halves load-bearing: the
  # aggregate exists AND it carries the exact context name that branch protection
  # requires. Matches `if: always()` and `if: ${{ always() }}`.
  def always_aggregate?(yaml, label)
    job = aggregate_job(yaml, label)
    !job.nil? && job["if"].to_s.match?(/always\s*\(\s*\)/)
  end

  # (f) [OPS.23] An aggregate that depends on the path-FILTER job must assert that
  # the filter itself SUCCEEDED — not merely that nothing failed.
  #
  # The filter carries no `if:`, so `success` is its ONLY legal result, while every
  # job it gates may legally be `skipped`. A guard shaped
  # `contains(needs.*.result, 'failure') || contains(needs.*.result, 'cancelled')`
  # therefore reads a skipped FILTER as an ordinary path-skip and reports green
  # having run nothing at all. `skipped` is the discriminator — NOT `cancelled`,
  # which that guard does catch, which is why "cancel the filter and watch" proves
  # nothing about this class.
  #
  # ⚠️ Declared ceiling, three parts. (1) This checks that a FAILING step is wired to
  # the filter's result, not that its condition is exactly `!= 'success'` — the shapes
  # are many (`!= 'success'`, `== 'skipped' || == 'cancelled'`), and pinning one
  # spelling would reject a correct rewrite. (2) It owes nothing when the aggregate
  # does not depend on the filter at all (dco.yml has no filter job). (3) It ranges
  # over :required entries ONLY, so an aggregate born outside the perimeter is out of
  # its reach — check (a) covers that for pull_request-triggered workflows, but a
  # push-only one (sbom.yml) is seen by neither. Measured clean when (f) landed: every
  # `contains(needs.*.result, …)` guard in the tree sits inside the required set.
  def filter_result_asserted?(yaml, label, filter: FILTER_JOB)
    job = aggregate_job(yaml, label)
    return true if job.nil? # absence is (c)'s finding, not this one's
    return true unless Array(job["needs"]).include?(filter)

    Array(job["steps"]).any? do |step|
      step.is_a?(Hash) &&
        step["if"].to_s.include?("needs.#{filter}.result") &&
        step["run"].to_s.include?("exit 1")
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

        unless filter_result_asserted?(parsed[base], meta)
          errors << ":required `#{base}` aggregate #{meta.inspect} depends on the " \
                    "`#{FILTER_JOB}` filter job but never asserts its RESULT — a " \
                    "`contains(needs.*.result, …)` guard reads a SKIPPED filter as an " \
                    "ordinary path-skip and reports green having run nothing (OPS.23). " \
                    "Add a failing step keyed on `needs.#{FILTER_JOB}.result`."
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

  # (d)+(e) prose-claim consistency — no token needed, so these DO run in CI.
  claim_violations = WorkflowGatePerimeter.count_claim_violations +
                     WorkflowGatePerimeter.flip_claim_violations
  required_n = WorkflowGatePerimeter::PERIMETER.count { |_b, (c, _m)| c == :required }
  if claim_violations.empty?
    puts "\nprose-claim consistency ✓ — every live claim agrees with PERIMETER " \
         "(#{required_n} required)."
  else
    puts "\nprose-claim consistency ✗ — #{claim_violations.size} site(s) disagree " \
         "with PERIMETER (#{required_n} required):"
  end

  if result[:errors].empty? && live_violations.empty? && claim_violations.empty?
    puts "\nworkflow_gate_perimeter ✓ — perimeter sound: every PR-gate classified, " \
         "no dead entry, every :required aggregate present" \
         "#{live ? " (+ live branch-protection verified)" : ""}."
    exit 0
  else
    warn "\nworkflow_gate_perimeter ✗ — gate-perimeter drift (OPS.14 / DOC-T.51):"
    (result[:errors] + live_violations + claim_violations).each { |e| warn "  · #{e}" }
    exit 1
  end
end
