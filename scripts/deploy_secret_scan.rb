#!/usr/bin/env ruby
# frozen_string_literal: true

# Deploy-secret scan (CI: ci.yml). Two never-drift invariants over the Akash SDL,
# so the secrets-at-rest latch cannot silently come undone:
#   A. No real secret LITERAL committed in any service env — secret-named vars must
#      stay REQUIRED_SECRET_NOT_SET placeholders / ${tpl}-vars. A committed key on a
#      PUBLIC repo is an irreversible leak.
#   B. The money-signing sextet is JOB-ONLY — never on the internet-facing web or
#      coap surface. `web3_network_guard` enforces this at RUNTIME (presence in the
#      signer process at boot); this makes it a CI gate on SDL PLACEMENT, closing
#      the "runtime, not CI" gap.
#
# Mirrors scripts/sdl_consistency_check.rb (pure Ruby+YAML; .tpl directives/${var}
# stripped before parsing).

require "yaml"

STATIC = "deploy/akash/deploy.yaml"
TPL    = "deploy/akash/deploy.yaml.tpl"

# Secret-bearing var-name suffixes. `_SECRET` subsumes `_HMAC_SECRET`/`_WEBHOOK_SECRET`;
# `_BASE64` catches GCP_SA_KEY_BASE64; `_RPC_URL`/`REDIS_URL` embed provider keys /
# passwords in the URL; `_TOKEN`/`_API_KEY` cover Grafana/service tokens. All current
# manifests keep these as REQUIRED_SECRET_NOT_SET / ${tpl}, so no false positives.
SECRET_NAME = /(_PRIVATE_KEY|_KEYPAIR|MASTER_KEY|SECRET_KEY_BASE|_SECRET|_PASSWORD|_TOKEN|_BASE64|_API_KEY|_RPC_URL|REDIS_URL)\z/
PLACEHOLDER = "REQUIRED_SECRET_NOT_SET"
TPL_MARKER  = "TPLVAR" # what load_tpl replaces ${var} with

SIGNING_SEXTET = %w[
  ORACLE_PRIVATE_KEY ORACLE_CELO_PRIVATE_KEY ORACLE_MINTER_PRIVATE_KEY
  ORACLE_SLASHER_PRIVATE_KEY ETHEREUM_ANCHOR_PRIVATE_KEY SOLANA_WALLET_KEYPAIR
].freeze

def load_tpl(path)
  text = File.read(path)
  text = text.gsub(/^%\{[^}]*\}/, "")
  text = text.gsub(/\$\{[^}]+\}/, TPL_MARKER)
  YAML.safe_load(text, aliases: true)
end

def env_pairs(sdl, svc)
  (sdl.dig("services", svc, "env") || []).map do |line|
    name, _, value = line.to_s.partition("=")
    [ name, value.strip ]
  end
end

def env_names(sdl, svc)
  env_pairs(sdl, svc).map(&:first)
end

failures = []

[ [ STATIC, YAML.safe_load_file(STATIC) ], [ TPL, load_tpl(TPL) ] ].each do |name, sdl|
  services = (sdl["services"] || {}).keys

  # Invariant A — no committed secret literal (covers a hex key or any stray value).
  services.each do |svc|
    env_pairs(sdl, svc).each do |var, value|
      next unless var =~ SECRET_NAME
      next if value == PLACEHOLDER || value == TPL_MARKER || value.empty?

      failures << "#{name}: #{svc}.#{var} carries a non-placeholder literal " \
                  "'#{value[0, 12]}…' — secret vars must be #{PLACEHOLDER} / ${tpl}-var"
    end
  end

  # Invariant B — signing sextet is job-only. Allow-list (every service EXCEPT job),
  # not a web/coap deny-list, so a future internet-facing service can't silently
  # escape the money-key gate by not being named here.
  (services - [ "job" ]).each do |svc|
    leaked = SIGNING_SEXTET & env_names(sdl, svc)
    failures << "#{name}: signing sextet #{leaked} on #{svc} env — must be JOB-ONLY" if leaked.any?
  end
  missing = SIGNING_SEXTET - env_names(sdl, "job")
  failures << "#{name}: signing sextet missing from job env: #{missing}" if missing.any?
end

# Invariant C — .dockerignore keeps secret files out of the PUBLIC GHCR image
# (a leaked RAILS_MASTER_KEY would decrypt a shipped credentials.yml.enc).
DOCKERIGNORE_MUST = [ "config/credentials.yml.enc", "config/master.key", "config/credentials/*.key" ].freeze
if File.exist?(".dockerignore")
  di = File.read(".dockerignore").lines.map(&:strip)
  DOCKERIGNORE_MUST.each do |pat|
    excluded = di.any? { |l| !l.start_with?("!") && l.sub(%r{\A/}, "") == pat }
    failures << ".dockerignore: no exclusion for #{pat} — would ship into the public image" unless excluded
  end
  negated = di.select { |l| l.start_with?("!") && l.match?(/credential|master\.key|\.enc/i) }
  failures << ".dockerignore: a negation re-includes a secret file: #{negated}" if negated.any?
else
  failures << ".dockerignore is missing entirely"
end

if failures.empty?
  puts "✓ Deploy-secret scan: no key literals; signing sextet job-only across both manifests"
else
  puts "DEPLOY-SECRET SCAN FAILED:"
  failures.each { |f| puts "  ✗ #{f}" }
  exit 1
end
