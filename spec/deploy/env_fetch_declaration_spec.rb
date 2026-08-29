# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "spec_helper"
require_relative "../support/repo_root"

# INF.12 drift guard. A money/web3 var read as ENV.fetch("X") with NO default raises KeyError
# on first use if absent — so it must reach the runtime on EVERY deploy path the code runs on,
# and for a SECRET that is a multi-link chain, not one surface:
#
#   clear var (contract address): config/deploy.yml env.clear                        (1 surface)
#   secret var (signing key):     config/deploy.yml env.secret →  .kamal/secrets-common (Kamal
#                                 resolves $VAR) → deploy workflow env: block (CI injects the
#                                 GitHub Secret)                                       (3 surfaces)
#
# A link missing on either path = a KeyError-at-first-mint on that surface, silent until runtime.
# verify-secrets covers only boot-critical PRESENCE (a subset); the deploy.yml↔secrets-common↔
# workflow chain is otherwise just a comment ("MUST mirror"). This closes the set-diff for the
# vars the code actually ENV.fetch'es, on every surface each needs. [OPS.37] The second,
# independent SDL declaration is gone with the platform — a narrower SURFACE, not less coverage:
# the deploy.yml example below already judges the same set.
#
# Exception: activation-gated aux signers — path dead until activation, key Console-injected
# then (never on any deploy surface — SEC.22/INF.22); ENV.fetch-without-default so activating
# without the key fails LOUD.
RSpec.describe "ENV.fetch-without-default reaches runtime on every surface (INF.12)" do # rubocop:disable RSpec/DescribeClass
  let(:activation_gated) { %w[ORACLE_ETHERISC_PRIVATE_KEY ORACLE_PURO_PRIVATE_KEY ORACLE_KLIMA_PRIVATE_KEY] }
  # ENV.fetch("X") NOT followed by "{" (block default); positional-default form never matches.
  let(:code_fetches) do
    Dir[REPO_ROOT.join("app/**/*.rb"), REPO_ROOT.join("lib/**/*.rb")]
      .flat_map { |f| File.read(f).scan(/ENV\.fetch\("([A-Z][A-Z0-9_]{2,})"\)(?!\s*\{)/).flatten }
      .uniq - activation_gated
  end
  let(:deploy_secret)  { names("config/deploy.yml", /^\s+-\s*([A-Z][A-Z0-9_]{2,})\s*$/) }
  let(:deploy_clear)   { names("config/deploy.yml", /^\s+([A-Z][A-Z0-9_]{2,}):/) }
  let(:secrets_common) { names(".kamal/secrets-common", /^([A-Z][A-Z0-9_]{2,})=/) }
  # The KEY (LHS) of `KEY: ${{ secrets.X }}` is what .kamal/secrets-common reads as $KEY — NOT
  # the secret name (RHS). A typo in the KEY (REDIS_URL:→REDIS_URI:, RHS intact) is the exact B1
  # empty-inject crash, so capture the LHS. This also picks up KEYs injected from a step output
  # (GCP_ARTIFACT_REGISTRY_KEY ← auth access_token), not just secrets.
  let(:workflow_env) do
    %w[.github/workflows/deploy.yml .github/workflows/deploy-production.yml]
      .flat_map { |p| names(p, /^\s+([A-Z][A-Z0-9_]{2,}):\s*\$\{\{/) }.uniq
  end

  def names(path, regex) = File.read(REPO_ROOT.join(path)).scan(regex).flatten.uniq



  it "is declared in config/deploy.yml (env.clear or env.secret)" do
    missing = code_fetches - deploy_secret - deploy_clear
    expect(missing).to be_empty, "code ENV.fetch not declared in config/deploy.yml: #{missing.join(', ')}"
  end

  # B1/INF.19 (the 4-month deploy-block root) generalised beyond the code-fetched vars: EVERY
  # env.secret var must resolve in .kamal/secrets-common ($VAR) AND be mapped as a workflow
  # env: KEY, else CI injects "" → boot crash behind a green verify. workflow_env captures the
  # LHS KEY, so a step-output-injected var (GCP_ARTIFACT_REGISTRY_KEY ← auth token) is covered
  # too — no exception needed. NOTE: workflow_env unions both workflows, so a var deliberately
  # absent from canopy vs forgotten there is not distinguished (LOW — deploy verify-secrets is a
  # second net; per-workflow split if it ever bites).
  it "every env.secret completes the Kamal chain — secrets-common AND a workflow env: block (B1/INF.19)" do
    missing_common   = deploy_secret - secrets_common
    missing_workflow = deploy_secret - workflow_env
    aggregate_failures do
      expect(missing_common).to be_empty, "in env.secret but not .kamal/secrets-common (Kamal $VAR unresolved): #{missing_common.join(', ')}"
      expect(missing_workflow).to be_empty, "in env.secret but not a deploy-workflow env: block (CI injects '' → boot crash, B1): #{missing_workflow.join(', ')}"
    end
  end

  it "keeps activation-gated aux keys OFF every deploy surface (Console-inject only — SEC.22)" do
    leaked = activation_gated & (deploy_secret + deploy_clear + secrets_common + workflow_env)
    expect(leaked).to be_empty, "activation-gated aux signer leaked onto a deploy surface: #{leaked.join(', ')}"
  end
end
