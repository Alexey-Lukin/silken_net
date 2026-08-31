# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "spec_helper"
require "yaml"
require "open3"
require_relative "../support/repo_root"

# [OPS.28] The `ruby` path-filter in `ci.yml` gates FIVE jobs (scan_ruby · lint · i18n_check ·
# test · feature-test). It was NARROWER than the perimeter those jobs actually judge, and the
# drift was silent by construction: a filter is a list of globs, a perimeter is whatever
# `bin/rubocop --list-target-files` returns, and nothing compared them.
#
# 🔴 WHAT THE GAP COST, measured 2026-08-31 (this is why the ⚖️ went to widen rather than to
# accept): twelve specs exist precisely to test `scripts/*.rb` — they `require_relative` or
# shell out to the script itself — and NONE of them ran when those scripts changed.
# ⊕ Evidence grade of that "twelve", because a bare number reads stronger than it is: the
# candidate set was SIXTEEN (specs mentioning `scripts/` at all); four were prose mentions
# only and were discarded by reading each one — precision 75%, counted by name, not by grep. Two of the
# twelve guard the offline verifiers an EXTERNAL AUDITOR runs against our evidence bundles
# (`scripts/verify_lineage_bundle.rb` ← spec/services/mrv/lineage_report_service_spec,
# `scripts/verify_archive_bundle.rb` ← spec/workers/telemetry_archive_batch_worker_spec), and
# both boot Rails, so the cheap alternative (add them to the named list in `docs.yml`, whose
# filter already carries `scripts/**`) could not reach them.
#
# 💰 Perimeter priced BEFORE switching on (00_05 §5): the widening fires on ≤4.2% of commits
# (58/1393 over 30d; 111/3157 over 90d — "≤" because CI filters on the PUSH diff and a push
# batches commits), at ~6 min wall / 10.4 min runner. This spec itself costs one
# `--list-target-files` run.
#
# 🔴 THIS SPEC LIVES IN THE `Docs` LANE, NOT IN `test`, AND THE REASON IS SELF-REFERENTIAL:
# a gate that catches "a file outside the `ruby` filter" cannot be gated BY that filter — it
# would be silent in exactly the case it exists for. Registered in `.github/workflows/docs.yml`
# (cross-tree step) + `00_06 §3`. ⛔ Do not "tidy" it into the quality-spec block of the `test`
# job: that move looks like consolidation and silently re-creates the blindness.
#
# 🔒 DECLARED CEILINGS — read both before trusting a green.
# (A) This judges COVERAGE of the rubocop target set, never the converse. A filter entry
#     matching files rubocop ignores (`db/**`, `spec/**` fixtures) is not flagged, and that is
#     deliberate: those entries exist for the `test` job, not for `lint`, and demanding a
#     bijection would fight the filter's real purpose.
# (B) A brand-new TOP-LEVEL directory containing `.rb` triggers NEITHER lane — neither filter
#     has a catch-all — so this gate first speaks on the next diff that touches an already
#     covered tree. That is a real hole, named rather than papered over: the gate ratchets an
#     existing perimeter, it does not discover a new root.
RSpec.describe "the ci.yml `ruby` filter covers every RuboCop target [OPS.28]" do # rubocop:disable RSpec/DescribeClass
  # dorny/paths-filter matches with picomatch, where a TRAILING `/**` is recursive. Ruby's
  # `File.fnmatch?` with FNM_PATHNAME is NOT: it matches exactly one level there, so a naive
  # port of the check would red on `app/**` vs `app/models/user.rb` — a false failure on the
  # oldest entry in the list. Mid-pattern `**/` agrees between the two (verified below), so
  # the trailing form is the only special case.
  def self.matches?(pattern, path)
    return path.start_with?("#{pattern.delete_suffix('/**')}/") if pattern.end_with?("/**")

    File.fnmatch?(pattern, path, File::FNM_PATHNAME | File::FNM_EXTGLOB)
  end

  let(:filter_patterns) do
    workflow = YAML.safe_load(File.read(REPO_ROOT.join(".github/workflows/ci.yml")), aliases: true)
    filters  = workflow.dig("jobs", "changes", "steps")
                       .filter_map { |step| step.dig("with", "filters") }
                       .first
    YAML.safe_load(filters).fetch("ruby")
  end

  let(:rubocop_targets) do
    out, status = Open3.capture2("bin/rubocop", "--list-target-files", chdir: REPO_ROOT.to_s)
    raise "rubocop --list-target-files failed (#{status.exitstatus})" unless status.success?

    out.lines(chomp: true).reject(&:empty?).map { |line| line.delete_prefix("#{REPO_ROOT}/") }
  end

  it "leaves no RuboCop target outside the filter (a scripts-only diff must still run `lint` and `test`)" do
    uncovered = rubocop_targets.reject { |path| filter_patterns.any? { |pat| self.class.matches?(pat, path) } }
    expect(uncovered).to be_empty,
                         "these RuboCop targets are OUTSIDE the ci.yml `ruby` filter, so a diff touching only " \
                         "them runs neither `lint` nor `test`: #{uncovered.sort.inspect}. Add a pattern " \
                         "(prefer a narrow `*.rb` glob so a non-Ruby change in that tree does not drag the " \
                         "Rails suite) — the gap this closed cost 12 unrun specs, 2 of them auditor-facing."
  end

  # 🔴 Both examples above are set-differences, and a set-difference against an EMPTY set is
  # green for the worst possible reason. Either side going empty (a renamed job key, a rubocop
  # config change, a YAML schema shift) would look exactly like compliance.
  it "judges non-empty sets on BOTH sides" do
    aggregate_failures do
      expect(filter_patterns.size).to be > 10
      expect(rubocop_targets.size).to be > 900
      expect(rubocop_targets).to include("config.ru")
    end
  end

  # The matcher is this gate's only piece of original logic, so it carries its own controls —
  # including the exact divergence that would have made the check lie.
  describe "the picomatch-vs-fnmatch correction" do
    it "treats a TRAILING `/**` as recursive (fnmatch alone would say false)" do
      expect(described_class_matches("app/**", "app/models/user.rb")).to be(true)
      expect(File.fnmatch?("app/**", "app/models/user.rb", File::FNM_PATHNAME)).to be(false)
    end

    it "keeps mid-pattern `**/` and exact names honest, and still says NO to a miss" do
      aggregate_failures do
        expect(described_class_matches("tools/**/*.rb", "tools/firmware/scc_rate.rb")).to be(true)
        expect(described_class_matches("tools/**/*.rb", "tools/ml/train.py")).to be(false)
        expect(described_class_matches("config.ru", "config.ru")).to be(true)
        expect(described_class_matches("scripts/**", "spec/quality/x.rb")).to be(false)
      end
    end
  end

  def described_class_matches(pattern, path) = self.class.matches?(pattern, path)
end
