# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "spec_helper"
require "yaml"
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
  let(:role_secret) { deploy_env(:secret, scope: :roles) }
  let(:role_clear)  { deploy_env(:clear,  scope: :roles) }
  let(:any_secret)  { deploy_env(:secret, scope: :all) }
  let(:any_clear)   { deploy_env(:clear,  scope: :all) }
  let(:secrets_common) { names(".kamal/secrets-common", /^([A-Z][A-Z0-9_]{2,})=/) }
  # The KEY (LHS) of `KEY: ${{ secrets.X }}` is what .kamal/secrets-common reads as $KEY — NOT
  # the secret name (RHS). A typo in the KEY (REDIS_URL:→REDIS_URI:, RHS intact) is the exact B1
  # empty-inject crash, so capture the LHS. This also picks up KEYs injected from a step output
  # (GCP_ARTIFACT_REGISTRY_KEY ← auth access_token), not just secrets.
  let(:workflow_env) do
    %w[.github/workflows/deploy.yml .github/workflows/deploy-production.yml]
      .flat_map { |p| names(p, /^\s+([A-Z][A-Z0-9_]{2,}):\s*\$\{\{/) }.uniq
  end

  # 🔴 [INF.27] YAML, not a line regex — and the difference is a FALSE GREEN, not tidiness.
  # The old anchors (`/^\s+-\s*NAME$/`, `/^\s+NAME:/`) are indentation-blind, so a var declared
  # ONLY under `accessories.*` or `registry.password` read as "declared" for the Rails roles.
  # Measured on the live tree 2026-08-30, that state held FIVE vars — `DEPLOYMENT_SLOT`,
  # `GCP_ARTIFACT_REGISTRY_KEY` and the three `GRAFANA_REMOTE_WRITE_*` — so an
  # `ENV.fetch("X")` in app/ or lib/ naming any of them passed this gate GREEN and would
  # KeyError at first use on web/job/coap. Exactly the B1 shape the gate exists to stop.
  #
  # 🔑 TWO SCOPES, because the three examples below ask DIFFERENT questions of one word:
  #   :roles — what an APP PROCESS can see (top-level `env` + `servers.*.env`). Accessories
  #            run in their own containers; their env never reaches Rails code.
  #   :all   — everything KAMAL must resolve (:roles + `accessories.*.env` + `registry.password`).
  #            Narrowing the chain-completeness and leak examples to :roles would have DROPPED
  #            coverage — those four accessory/registry secrets still need a `$VAR` in
  #            secrets-common and a workflow `env:` key, and a leaked aux signer is a leak
  #            wherever it lands.
  def deploy_env(kind, scope:)
    cfg = YAML.safe_load(File.read(REPO_ROOT.join("config/deploy.yml")), aliases: true)
    blocks = [ cfg["env"], *(cfg["servers"] || {}).values.grep(Hash).map { |r| r["env"] } ]
    extras = []
    if scope == :all
      blocks += (cfg["accessories"] || {}).values.grep(Hash).map { |a| a["env"] }
      # `registry.password` and `proxy.ssl.{certificate_pem,private_key_pem}` are Kamal SECRET
      # NAMES that live OUTSIDE any `env:` block — Kamal still has to resolve each from
      # `.kamal/secrets-common`, and CI still has to inject each as a workflow `env:` key.
      # ⚠️ The proxy pair is what makes the INF.4 origin-certificate contract ENFORCED rather
      # than commented, and the block went LIVE 2026-08-31 — so this gate now genuinely demands
      # moves (2) and (3) of its five, instead of trusting whoever reads the comment. (Until
      # that morning it contributed nothing: a commented block is invisible to YAML, which was
      # correct, not a hole. Both halves of this sentence were written in the future tense and
      # became false the moment the cert shipped.)
      extras = kind == :secret ? Array(cfg.dig("registry", "password")) + [ cfg.dig("proxy", "ssl", "certificate_pem"), cfg.dig("proxy", "ssl", "private_key_pem") ].compact : []
    end
    named = blocks.compact.flat_map do |env|
      kind == :clear ? (env["clear"] || {}).keys : Array(env["secret"])
    end
    (named + extras).grep(/\A[A-Z][A-Z0-9_]{2,}\z/).uniq
  end


  def names(path, regex) = File.read(REPO_ROOT.join(path)).scan(regex).flatten.uniq



  it "is declared where a Rails ROLE can see it (not merely somewhere in config/deploy.yml)" do
    missing = code_fetches - role_secret - role_clear
    expect(missing).to be_empty,
                       "code ENV.fetch not reachable by web/job/coap: #{missing.join(', ')} " \
                       "(declared only on an accessory or the registry does NOT count — INF.27)"
  end

  # ⚠️ Size pin. Every example here is a set-difference, and a set-difference against an
  # EMPTY declared set is green for the worst possible reason. The YAML reader above replaced
  # a regex; if it ever returns nothing (a Kamal schema change, a renamed block), the three
  # examples would all pass while judging nothing at all.
  it "reads a non-empty declaration set on both scopes" do
    aggregate_failures do
      expect(code_fetches.size).to be > 5
      expect(role_secret.size).to be > 15
      expect(role_clear.size).to be > 10
      # Named, not counted: `:all` must genuinely be WIDER than `:roles`, and naming the members
      # keeps the pin honest when the set grows (a frozen size would have RED-ed on the INF.4
      # proxy-cert pair for the wrong reason — that pair landed 2026-08-31 and is named below).
      expect(any_secret - role_secret).to include(
        "GCP_ARTIFACT_REGISTRY_KEY", "GRAFANA_REMOTE_WRITE_URL",
        "GRAFANA_REMOTE_WRITE_USERNAME", "GRAFANA_REMOTE_WRITE_TOKEN",
        "TLS_ORIGIN_CERT_PEM", "TLS_ORIGIN_KEY_PEM"
      )
    end
  end

  # 🔴 [INF.4 2026-08-31] The chain above proves each proxy-cert name RESOLVES; this proves the
  # deploy REFUSES when its value is empty — a different axis, and the one that was missing.
  # Mechanism: `.kamal/secrets-common` declares both names, so `Kamal::Secrets#[]` never raises
  # "Secret not found"; it returns "". `Kamal::Cli::App::SslCertificates#run` then guards with
  # `if cert_content = …`, and "" is truthy in Ruby — kamal uploads an EMPTY cert.pem/key.pem
  # at mode 0644, kamal-proxy cannot serve TLS, and Cloudflare (Full (strict) on both zones)
  # answers 521/525 on every request behind a fully GREEN deploy. Before this pin neither
  # BOOT_CRITICAL nor RUNTIME named them, so there was not even a `::warning::`.
  it "gates the origin-cert pair as BOOT-CRITICAL in both deploy workflows (empty ⇒ silent 521)" do
    cfg = YAML.safe_load(File.read(REPO_ROOT.join("config/deploy.yml")), aliases: true)
    pair = [ cfg.dig("proxy", "ssl", "certificate_pem"), cfg.dig("proxy", "ssl", "private_key_pem") ].compact
    expect(pair.size).to eq(2), "config/deploy.yml no longer declares a custom proxy.ssl pair — " \
                                "this pin judges nothing; re-read INF.4 before deleting it"

    %w[.github/workflows/deploy.yml .github/workflows/deploy-production.yml].each do |path|
      declared = File.read(REPO_ROOT.join(path))[/^\s*BOOT_CRITICAL="([^"]*)"/, 1].to_s.split
      expect(declared).to include(*pair),
                          "#{path}: BOOT_CRITICAL omits #{(pair - declared).inspect}. An unset value is " \
                          "injected as \"\", kamal uploads an EMPTY certificate, and the origin answers " \
                          "521/525 behind a green deploy — verify-secrets is the only thing that can see it."
    end
  end

  # B1/INF.19 (the 4-month deploy-block root) generalised beyond the code-fetched vars: EVERY
  # env.secret var must resolve in .kamal/secrets-common ($VAR) AND be mapped as a workflow
  # env: KEY, else CI injects "" → boot crash behind a green verify. workflow_env captures the
  # LHS KEY, so a step-output-injected var (GCP_ARTIFACT_REGISTRY_KEY ← auth token) is covered
  # too — no exception needed. NOTE: workflow_env unions both workflows, so a var deliberately
  # absent from canopy vs forgotten there is not distinguished (LOW — deploy verify-secrets is a
  # second net; per-workflow split if it ever bites).
  it "every env.secret completes the Kamal chain — secrets-common AND a workflow env: block (B1/INF.19)" do
    missing_common   = any_secret - secrets_common
    missing_workflow = any_secret - workflow_env
    aggregate_failures do
      expect(missing_common).to be_empty, "in env.secret but not .kamal/secrets-common (Kamal $VAR unresolved): #{missing_common.join(', ')}"
      expect(missing_workflow).to be_empty, "in env.secret but not a deploy-workflow env: block (CI injects '' → boot crash, B1): #{missing_workflow.join(', ')}"
    end
  end

  it "keeps activation-gated aux keys OFF every deploy surface (Console-inject only — SEC.22)" do
    leaked = activation_gated & (any_secret + any_clear + secrets_common + workflow_env)
    expect(leaked).to be_empty, "activation-gated aux signer leaked onto a deploy surface: #{leaked.join(', ')}"
  end
end
