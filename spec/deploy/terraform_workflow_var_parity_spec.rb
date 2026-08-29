# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "spec_helper"
require_relative "../support/repo_root"

# OPS.11 drift guard. billing.tf uses `count = var.billing_account_id != "" ? 1 : 0` — a terraform
# apply/plan with that var EMPTY silently sets count→0 and DESTROYS the GCP billing budget (a
# cost-safety control). Every workflow that runs terraform with real vars must pass every such
# count-guarded TF_VAR, or a dropped line / a new 4th apply-workflow tears the budget down GREEN.
# This is the same "workflow-unmapped var → silent breakage" class env_fetch_declaration_spec
# (INF.12/B1) guards for Ruby ENV.fetch, applied to the TF_VAR_* surface — sharper failure mode
# (silent teardown of a live control, not a boot-crash). terraform_validate is offline
# (init -backend=false) → it can't catch this; only var-passing workflows can teardown.
RSpec.describe "count-guarded TF_VARs reach every terraform-var workflow (OPS.11)" do # rubocop:disable RSpec/DescribeClass
  # Vars whose terraform resource is count-gated on non-empty — empty ⇒ destroyed.
  let(:guarded_vars) do
    Dir[REPO_ROOT.join("terraform/**/*.tf")]
      .flat_map { |f| File.read(f).scan(/count\s*=\s*var\.([a-z_]+)\s*!=\s*""/).flatten }.uniq
  end

  # A workflow that passes ANY TF_VAR runs terraform against real vars (validate-only passes none),
  # so it can create/destroy — a new apply-workflow is auto-covered without editing this spec.
  #
  # 🔴 Membership is decided by an ASSIGNMENT (`TF_VAR_x: …` at line start, YAML-indented),
  # never by the token appearing anywhere in the file — and that distinction is load-bearing,
  # not tidiness. [INF.22] removed the `terraform` job from both deploy workflows and, with it,
  # their `TF_VAR_*` block; the comment explaining WHY the block is gone necessarily NAMES the
  # token, so a substring test re-admitted both workflows as "terraform workflows" and demanded
  # vars they no longer pass. The gate was judging PROSE while claiming to judge CONFIG — one
  # token living in two domains. Narrowing it costs nothing (a real workflow assigns the var;
  # only prose mentions it bare) and it makes the population honest.
  let(:tf_var_assignment) { /^\s+TF_VAR_([a-z_]+)\s*:/ }

  let(:tf_workflows) do
    Dir[REPO_ROOT.join(".github/workflows/*.yml")].select { |f| File.read(f).match?(tf_var_assignment) }
  end

  it "is non-vacuous (found count-guarded vars AND terraform-var workflows)" do
    aggregate_failures do
      expect(guarded_vars).not_to be_empty
      expect(tf_workflows).not_to be_empty
    end
  end

  it "every terraform-var workflow passes every count-guarded var (empty ⇒ resource teardown)" do
    missing = tf_workflows.flat_map do |wf|
      # Same axis as membership above: an assignment counts, a mention does not — otherwise a
      # workflow could "pass" a guarded var by naming it in a comment.
      passed = File.read(wf).scan(tf_var_assignment).flatten
      (guarded_vars - passed).map { |v| "#{File.basename(wf)}: TF_VAR_#{v}" }
    end
    expect(missing).to be_empty,
                       "count-guarded TF_VAR missing from a terraform workflow — empty var → count=0 → " \
                       "resource DESTROYED (OPS.11 budget teardown): #{missing.join(', ')}"
  end
end
