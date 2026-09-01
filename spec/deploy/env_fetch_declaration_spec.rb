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
  # 🔑 THREE SCOPES, because the examples below ask DIFFERENT questions of one word:
  #   :global — ONLY the top-level `env`, i.e. what EVERY role on EVERY slot inherits. This is
  #            the scope the deploy-STEP example needs: `servers.job.env.secret` is correctly
  #            absent from canopy (web-only by construction), so demanding the union there
  #            would red a correct file, while every global entry must be mapped on both.
  #   :roles — what an APP PROCESS can see (top-level `env` + `servers.*.env`). Accessories
  #            run in their own containers; their env never reaches Rails code.
  #   :all   — everything KAMAL must resolve (:roles + `accessories.*.env` + `registry.password`).
  #            Narrowing the chain-completeness and leak examples to :roles would have DROPPED
  #            coverage — those four accessory/registry secrets still need a `$VAR` in
  #            secrets-common and a workflow `env:` key, and a leaked aux signer is a leak
  #            wherever it lands.
  def deploy_env(kind, scope:)
    cfg = YAML.safe_load(File.read(REPO_ROOT.join("config/deploy.yml")), aliases: true)
    blocks = [ cfg["env"] ]
    blocks += (cfg["servers"] || {}).values.grep(Hash).map { |r| r["env"] } unless scope == :global
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

  # The `env:` KEYS of the one step that actually ships the container, per workflow.
  # YAML, not a line regex, for the same reason the declaration reader is YAML [INF.27]: a
  # regex over `env:` is indentation-blind and cannot tell WHICH job/step a key belongs to —
  # which is precisely the distinction this example exists to make.
  def deploy_step_envs
    %w[.github/workflows/deploy.yml .github/workflows/deploy-production.yml].to_h do |path|
      wf = YAML.safe_load(File.read(REPO_ROOT.join(path)), aliases: true)
      step = (wf["jobs"] || {}).values.grep(Hash)
                               .flat_map { |j| Array(j["steps"]) }.grep(Hash)
                               .find { |s| s["name"].to_s.start_with?("Kamal Deploy to") }
      [ File.basename(path), (step&.dig("env") || {}).keys ]
    end
  end



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
  # too — no exception needed. NOTE: workflow_env unions both workflows AND every `env:` block
  # inside them, so it answers "is this mapped ANYWHERE", never "does it reach the deploy".
  # 🔴 That second question is the one that bit (2026-09-01) — this note used to end "LOW …
  # per-workflow split if it ever bites", and the union it excused was not the workflow one
  # but the STEP one: `TURBO_SIGNED_STREAM_KEY` sat in `verify-secrets` on BOTH files and in
  # neither `Kamal Deploy to …` step, so the gate that CHECKS the secret had it and the step
  # that DELIVERS it did not, at a steady green. Kept as-is on purpose (it is the wider net,
  # and it also judges secrets-common); the narrow question now has its own example below.
  it "every env.secret completes the Kamal chain — secrets-common AND a workflow env: block (B1/INF.19)" do
    missing_common   = any_secret - secrets_common
    missing_workflow = any_secret - workflow_env
    aggregate_failures do
      expect(missing_common).to be_empty, "in env.secret but not .kamal/secrets-common (Kamal $VAR unresolved): #{missing_common.join(', ')}"
      expect(missing_workflow).to be_empty, "in env.secret but not a deploy-workflow env: block (CI injects '' → boot crash, B1): #{missing_workflow.join(', ')}"
    end
  end

  # 🔴 The narrow half of B1, and the one the union above cannot ask: a var must reach the
  # container, and the only step that carries it there is `kamal deploy`. Presence in the
  # `verify-secrets` job proves the SECRET EXISTS; it says nothing about DELIVERY, and the two
  # live in different jobs — so a var mapped only in the checker is injected "" by
  # secrets-common at deploy time. Judged PER WORKFLOW: the union is what hid this.
  #
  # Scope is the GLOBAL `env.secret` deliberately — `servers.job.env.secret` (the money
  # quintet) is correctly absent from canopy, which is structurally web-only (deploy_secret_scan
  # invariant B3), so demanding it here would red a correct file. Every global entry, by
  # contrast, is inherited by every role on BOTH slots and must be mapped on both.
  #
  # 🔒 Declared ceiling: this judges the step's env KEYS, never their values or their RHS —
  # `FOO: ${{ secrets.BAR }}` with the wrong secret name passes. That axis belongs to the
  # existing LHS-capture example above, which is why both stay.
  it "every secret the slot NEEDS reaches its `kamal deploy` STEP — per workflow (B1, delivery half)" do
    global_secret = deploy_env(:secret, scope: :global)
    quintet       = deploy_env(:secret, scope: :roles) - global_secret
    tls_pair      = %w[TLS_ORIGIN_CERT_PEM TLS_ORIGIN_KEY_PEM]
    # Expected set is PER SLOT, and that is the whole point of this rewrite. An earlier
    # version demanded only the GLOBAL set on both, and justified exempting the rest by
    # saying the parity gate covered it — while the parity gate exempts this very step and
    # pointed BACK here. Two gates each deferring to the other is the same mutual-deferral
    # shape this session was fixing, one level up: the quintet's delivery to production and
    # the TLS pair's delivery to either slot were gated by NOTHING. Caught by adversarial
    # review of the commit that introduced it, not by any instrument.
    expected = {
      "deploy.yml"            => global_secret + tls_pair,           # canopy: web-only, no job role
      "deploy-production.yml" => global_secret + quintet + tls_pair  # production: carries the signer
    }
    steps = deploy_step_envs
    aggregate_failures do
      expect(steps.keys.sort).to eq(expected.keys.sort), "deploy-step parser drift: #{steps.keys.inspect}"
      expect(global_secret.size).to be > 10
      # Composition pin, not just cardinality: "5 members" is green on five WRONG names.
      expect(quintet.sort).to eq(%w[ETHEREUM_ANCHOR_PRIVATE_KEY ORACLE_CELO_PRIVATE_KEY
                                    ORACLE_MINTER_PRIVATE_KEY ORACLE_SLASHER_PRIVATE_KEY
                                    SOLANA_WALLET_KEYPAIR].sort),
                                 "the job-only signer set moved — re-read config/deploy.yml servers.job"
      steps.each do |label, keys|
        expect(keys.size).to be > 15, "#{label}: deploy-step env block looks empty (#{keys.size} keys) — parser drift?"
        missing = expected.fetch(label) - keys
        expect(missing).to be_empty,
                           "#{label}: this slot NEEDS these and the deploy step does not map them: " \
                           "#{missing.join(', ')} — `.kamal/secrets-common` resolves them from the CI " \
                           "shell, so they arrive EMPTY in the container (B1)."
      end
      # 🔒 The mirror, and it is a SECURITY assertion rather than a delivery one: canopy is
      # structurally web-only (`deploy_secret_scan` invariant B3), so the money/signing quintet
      # must never be handed to its deploy step. Absence here is the isolation, not an omission.
      leaked = quintet & steps.fetch("deploy.yml")
      expect(leaked).to be_empty,
                        "canopy's deploy step maps the money/signing quintet: #{leaked.join(', ')} — " \
                        "staging must not be able to sign (INF.22 environment-scoping)."
    end
  end

  it "keeps activation-gated aux keys OFF every deploy surface (Console-inject only — SEC.22)" do
    leaked = activation_gated & (any_secret + any_clear + secrets_common + workflow_env)
    expect(leaked).to be_empty, "activation-gated aux signer leaked onto a deploy surface: #{leaked.join(', ')}"
  end
end
