#!/usr/bin/env ruby
# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# GitHub deploy-secret SCOPE auditor (S1.1 verify-half). Read-only preflight over
# the LIVE GitHub secret surface via `gh` — asserts the scope invariants that
# `verify-secrets` (CI, presence-only) structurally CANNOT:
#   1. Money-signing quintet lives in Environment `production` ONLY. A copy at
#      repo-level is visible to EVERY workflow (deploy stays green — the R3c
#      wrong-home isolation trap). Mirror of scripts/deploy_secret_scan.rb's
#      SIGNING_QUINTET; env-scoped per docs/06_04 §1 header.
#   2. Retired ORACLE_PRIVATE_KEY is gone everywhere (INF.22 — runtime guard
#      refuses it; here it is a plaintext zombie to remove).
#   3. Keyless-WIF ids are repo VARIABLES, not Secrets — `verify-secrets` reads
#      `vars.GCP_*`; a same-named Secret leaves the deploy-gate mis-signalling.
#
# `gh secret list` returns NAMES only (GitHub never exposes secret VALUES), so this
# tool is value-safe by construction — it complements, not replaces, 06_04 §1.
# Run AFTER setting secrets, BEFORE the first deploy:
#   ruby scripts/audit_deploy_secret_scope.rb              # live audit via gh
#   ruby scripts/audit_deploy_secret_scope.rb --self-test  # classifier only, no gh
#
# Needs: `gh` authed with repo admin (secret/variable read), run from repo root.
# Exit 0 = clean · 1 = scope breach · 2 = gh/setup error. NOT a CI gate (needs
# admin token + set secrets); presence stays owned by `verify-secrets`.

# Env-scoped money/signing quintet (docs/06_04 §1; = deploy_secret_scan.rb SIGNING_QUINTET).
SIGNING_QUINTET = %w[
  ORACLE_MINTER_PRIVATE_KEY ORACLE_SLASHER_PRIVATE_KEY ORACLE_CELO_PRIVATE_KEY
  ETHEREUM_ANCHOR_PRIVATE_KEY SOLANA_WALLET_KEYPAIR
].freeze

RETIRED    = %w[ORACLE_PRIVATE_KEY].freeze                                # INF.22 retired
WIF_VARS   = %w[GCP_WORKLOAD_IDENTITY_PROVIDER GCP_SERVICE_ACCOUNT].freeze # repo Variables, not Secrets
# [INF.22] These are INSTANCE overrides, not auto-derive: Upstash exposes one logical
# database, so both consumers read REDIS_URL and are separated by key prefix. Setting
# either points that consumer at a SEPARATE Redis instance — the only real isolation
# from memory pressure. A placeholder/empty value is truthy to ENV.fetch and silences
# the fallback, which is why presence alone is worth a warning.
INSTANCE_OVERRIDE = %w[KREDIS_REDIS_URL RACK_ATTACK_REDIS_URL].freeze

# Pure classifier over NAME sets only. Returns [errors, warnings].
# org_secrets = [] on a personal account (no org scope possible); a list if the repo lives under
# a GitHub org (an ORG-level money key is visible to every repo/workflow — same R3c class as repo).
def audit(repo_secrets:, env_secrets:, variables:, org_secrets: [])
  errors = []
  warnings = []

  SIGNING_QUINTET.each do |k|
    if repo_secrets.include?(k)
      errors << "#{k} = REPO-level secret — money-ключі мусять бути Environment `production`-scoped ТІЛЬКИ " \
                "(repo-level видимий кожному workflow = R3c isolation breach). Перенеси: " \
                "gh secret set #{k} --env production && gh secret delete #{k}"
    end
    if org_secrets.include?(k)
      errors << "#{k} = ORG-level secret — money-ключі мусять бути Environment `production`-scoped ТІЛЬКИ " \
                "(org-scope видимий кожному repo+workflow орг = R3c breach). Перенеси: " \
                "gh secret set #{k} --env production && gh secret delete #{k} --org <org>"
    end
    warnings << "#{k} відсутній в Environment `production` — deploy-production не підпише поки не заведений " \
                "(gh secret set #{k} --env production)" unless env_secrets.include?(k)
  end

  RETIRED.each do |k|
    warnings << "#{k} присутній (repo) — RETIRED [INF.22], прибери зомбі (gh secret delete #{k})" if repo_secrets.include?(k)
    warnings << "#{k} присутній (env production) — RETIRED [INF.22], прибери (gh secret delete #{k} --env production)" if env_secrets.include?(k)
  end

  WIF_VARS.each do |k|
    if repo_secrets.include?(k) || env_secrets.include?(k)
      warnings << "#{k} заведений як Secret — keyless-WIF id це repo VARIABLE (verify-secrets читає vars.#{k}); " \
                  "постав як variable, видали secret"
    end
    warnings << "#{k} не заведений як repo Variable — deploy-gate сигнал відсутній " \
                "(gh variable set #{k} <з terraform output>)" unless variables.include?(k)
  end

  INSTANCE_OVERRIDE.each do |k|
    warnings << "#{k} заведений — переконайся, що вказує на ОКРЕМИЙ Redis-інстанс; порожній/placeholder перебив би " \
                "фолбек на REDIS_URL (config/redis/shared.yml). Наразі workflow-unmapped = інертний." if repo_secrets.include?(k)
  end

  [ errors, warnings ]
end

# --- gh gathering (live) -----------------------------------------------------
def gh_names!(args)
  out = `gh #{args} --json name -q '.[].name' 2>&1`
  unless $?.success?
    warn "✗ gh error (gh #{args}):"
    warn out
    warn "  Потрібно: gh auth login + repo admin (secret/variable read). Запуск із кореня репо."
    exit 2
  end
  out.split("\n").map(&:strip).reject(&:empty?)
end

def gh_names_soft(args)
  out = `gh #{args} --json name -q '.[].name' 2>/dev/null`
  $?.success? ? out.split("\n").map(&:strip).reject(&:empty?) : nil
end

# --- self-test (offline; one runnable check per CLAUDE.md §4) -----------------
def self_test
  q = SIGNING_QUINTET
  cases = [
    [ "clean",          { repo_secrets: [], env_secrets: q, variables: WIF_VARS },                             0, 0 ],
    [ "money at repo",  { repo_secrets: [ "ORACLE_MINTER_PRIVATE_KEY" ], env_secrets: q, variables: WIF_VARS }, 1, 0 ],
    [ "money at org",   { repo_secrets: [], env_secrets: q, variables: WIF_VARS, org_secrets: [ "ORACLE_MINTER_PRIVATE_KEY" ] }, 1, 0 ],
    [ "money miss env", { repo_secrets: [], env_secrets: q - [ "SOLANA_WALLET_KEYPAIR" ], variables: WIF_VARS }, 0, 1 ],
    [ "retired zombie", { repo_secrets: [ "ORACLE_PRIVATE_KEY" ], env_secrets: q, variables: WIF_VARS },        0, 1 ],
    [ "wif as secret",  { repo_secrets: WIF_VARS, env_secrets: q, variables: [] },                             0, 4 ],
    [ "kredis footgun", { repo_secrets: [ "KREDIS_REDIS_URL" ], env_secrets: q, variables: WIF_VARS },          0, 1 ]
  ]
  ok = true
  cases.each do |desc, args, exp_e, exp_w|
    e, w = audit(**args)
    pass = e.size == exp_e && w.size == exp_w
    ok &&= pass
    puts "#{pass ? '✓' : '✗'} #{desc}: errors #{e.size}/#{exp_e}, warnings #{w.size}/#{exp_w}"
    (e + w).each { |m| puts "    · #{m}" } unless pass
  end
  puts ok ? "✅ self-test: класифікатор коректний" : "❌ self-test FAILED"
  exit(ok ? 0 : 1)
end

self_test if ARGV.include?("--self-test")

# --- live audit --------------------------------------------------------------
repo = gh_names!("secret list")
vars = gh_names!("variable list")
env  = gh_names_soft("secret list --env production")
if env.nil?
  puts "⚠ Environment `production` не знайдено/недоступне — money-квінтет ще не можна скоупити (створи env: 06_04 §1)."
  env = []
end

# Org-level scope: only if the repo's owner is a GitHub organization (a personal account has no
# org secrets). An org-level money key is the same R3c breach as repo-level (visible org-wide).
#
# [DOC-T.64] Both look-ups below used to fail SILENTLY into `org = []`, which is
# indistinguishable from "audited the org and found nothing" — and the run then printed
# `✓ Scope-audit clean` over an axis it never looked at. The honest twin is seven lines up:
# the `env.nil?` block says out loud what it could not check. Same shape here.
owner_out = `gh repo view --json owner -q '.owner.login' 2>&1`
unless $?.success?
  warn "✗ gh error (repo view): #{owner_out.strip}"
  warn "  Власника репо не визначено → org-вісь НЕ перевірена; вердикт нижче був би про меншу множину."
  exit 2
end
owner = owner_out.strip
org = owner.empty? ? nil : gh_names_soft("secret list --org #{owner}")
if org.nil?
  # Two causes share this one channel — personal account (nothing to audit) and missing
  # `admin:org` scope (plenty to audit, no access). We cannot tell them apart, so we say so
  # rather than pick the comfortable reading.
  puts "⚠ Org-секрети недоступні (особистий акаунт АБО бракує `admin:org`) — org-вісь НЕ перевірена; «clean» нижче її не покриває."
  org = []
end

errors, warnings = audit(repo_secrets: repo, env_secrets: env, variables: vars, org_secrets: org)
warnings.each { |w| puts "⚠ #{w}" }

if errors.empty?
  puts "✓ Scope-audit clean: money-квінтет env-scoped (не repo) · WIF = Variables · retired ∅. #{warnings.size} warn."
  exit 0
else
  puts "SCOPE-AUDIT FAILED (#{errors.size}):"
  errors.each { |e| puts "  ✗ #{e}" }
  exit 1
end
