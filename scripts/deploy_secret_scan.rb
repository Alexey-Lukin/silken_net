#!/usr/bin/env ruby
# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Deploy-secret scan (CI: ci.yml). Never-drift invariants over the Kamal chain + the
# Ingress Anchor coap.env heredoc, so the secrets-at-rest latch cannot silently come undone:
#   A. No real secret LITERAL committed on any env surface — a secret-named var must stay a
#      REQUIRED_SECRET_NOT_SET placeholder, a shell reference ($VAR), or a ${terraform} interp.
#      A committed key on a PUBLIC repo is an irreversible leak.
#   B. The money-signing quintet is JOB-ONLY — never on the internet-facing web/coap surface,
#      and never in the GLOBAL env.secret. Security::Web3NetworkGuard enforces PRESENCE in the
#      signer process at runtime; this is the CI gate on PLACEMENT.
#      🔴 The global half has no ancestor and is the sharper one: the retired Akash SDL gave
#      every service its own env block with no shared bucket, but Kamal's top-level env.secret
#      is INHERITED BY EVERY ROLE (config/deploy.yml names `coap` as a role with no override).
#      So retargeting this gate off the SDL made it judge MORE, not less [OPS.37].
#   B2. The retired ORACLE_PRIVATE_KEY [INF.22] must not resurface as a STRUCTURAL key
#      (a key/name, never a grep — the name legitimately appears in prose comments).
#   B3. config/deploy.canopy.yml `servers:` must stay the ARRAY form. Kamal's destination
#      deep_merge REPLACES an array but UNIONS hash keys, so a hash here would silently inherit
#      the base `job` role — quintet included — into a leg whose secrets are production-scoped
#      → present-empty inject → Web3NetworkGuard raise on boot. This is the one live Kamal
#      instance of the "role declared but not where you think" class that the retired
#      sdl_consistency_check carried [OPS.37].
#      🔒 DECLARED CEILING (2026-08-29): this rule is WIDER than its own ground, and the gap
#      matters because it forbids a legitimate fix. The ground is "canopy must not INHERIT
#      the money quintet"; the rule bans the HASH FORM. A canopy `job:` role carrying its
#      OWN `env.secret:` array would satisfy the ground — Rails `deep_merge!` REPLACES
#      arrays, the very mechanism this invariant already leans on. So do not read a red
#      B3 as "canopy may never have a job role": read it as "canopy must not inherit one
#      silently". Narrowing it is gated on the canopy-shape decision (00_07, OPS.37 ⚖️ leg),
#      not on this file. ⚠️ Until 2026-09-02 the sharper reason the shape held was NOT in
#      this gate: canopy mapped the SAME mainnet RPC secrets as production, so a job role on
#      those keys would have signed on MAINNET from staging. B4 now remaps the RPC quartet,
#      so what a `job:` role still lacks is a TESTNET signer set of its own — the order the
#      founder ratified (keys first, role second; 00_07 OPS.37) is what this ceiling waits on.
#   B4. .kamal/secrets.canopy must remap EVERY shared external resource from its CANOPY_* twin
#      with a LOUD placeholder fallback — NEVER a silent fall-through to the production name.
#      🔴 The fallback's FORM is `$(printf '%s' "\${TWIN:-MARKER}")`, not `${TWIN:-MARKER}`: this
#      gate blessed the bare form twice (08-31, 09-02) reading it as TEXT, and Kamal's Dotenv
#      parser shipped `<value>:-MARKER}` on the first boot. B5 below forbids the bare form; the
#      parser-executed proof is spec/deploy/kamal_secrets_parse_spec.rb — a text gate cannot be it.
#   B5. No bare `${VAR:-…}` / `${VAR:=…}` in either shell-form secrets file (the anchor heredoc is
#      terraform-interpolated and exempt). The same defect delivered RAILS_MASTER_KEY as `<key>:-}`.
#      REDIS_URL first (2026-08-31: canopy talking to PRODUCTION Redis); the RPC quartet
#      ALCHEMY_POLYGON / ALCHEMY_ETHEREUM / SOLANA / CELO joined 2026-09-02 [INF.27 move (2)]:
#      a testnet slot handed a mainnet endpoint is what the chain axis REFUSES, and a refusal
#      is a detector, not an isolation — this overlay is the isolation. Structural, not
#      CI-only: a local `kamal deploy -d canopy` resolves secrets from the operator's own
#      shell, so the overlay is the only thing standing in that path.
#   D. No present-empty env (`VAR=` / `VAR:` with a blank value). Present-but-empty is worse
#      than absent: it silences autodetect/derive (RELEASE_VERSION→Sentry, REDIS_URL→Kredis,
#      PROMETHEUS_AUTH→known-value bypass) — the recurring B1 class that cost a 4-month block.
#   C. The two IGNORE files keep secret material out of the two public places it must never
#      reach: `.dockerignore` → the PUBLIC GHCR image, `.gitignore` → the PUBLIC git history.
#      The pair is deliberate, not redundant — the docker build context IS the workspace, so
#      one stops the IMAGE and the other stops the COMMIT, and neither implies the other.
#      🔴 `.gitignore` joined on 2026-09-01 [S1.1]: its `gha-creds-*.json` rule guards the LIVE
#      WIF credential that `google-github-actions/auth` writes INTO the workspace, and it had
#      no carrier at all — the tracker leg named only the .dockerignore half.
#
# Surfaces (post-OPS.37 — the Akash SDL is gone; the Kamal chain is the primary runtime):
#   config/deploy.yml · config/deploy.canopy.yml · .kamal/secrets-common ·
#   terraform/compute.tf COAP_ENV heredoc · .dockerignore · .gitignore.
#   ⚠️ Every subject here must appear in BOTH triggers — the `alloy` path-filter in ci.yml and
#   the pattern in .githooks/pre-push — or the gate does not run on the diff it guards (four of
#   five sat unwatched until 2026-08-30). 🔴 The relation is ⊆, NOT ≡, and the earlier wording
#   said ≡: the triggers legitimately carry MORE (`deploy/**`, `Dockerfile`, and — ci only — the
#   script itself), so a reader dutifully "restoring equality" would delete live trigger paths.
#   The heredoc's PRESENCE contract lives in
#   spec/deploy/anchor_coap_env_spec.rb (which names must/mustn't be there); only the FORM OF
#   VALUES is judged here — deliberately two predicates, one grammar (borrowed byte-for-byte
#   from that spec so the heredoc never gets a second, divergent parser).
#
# ⚠️ Declared vacuum: invariant A over YAML env.clear currently has ZERO subjects (no
# secret-named var lives in a clear block). It is a standing guardrail against a future
# env.clear secret, NOT coverage — do not read its green as "clear blocks were checked".
# SUBJECT_FLOOR below guards the non-vacuous half: a broken text parse returns an empty set
# and prints ✓ (guard-craft #47).

# ✅ MUTATION-VERIFIED 2026-08-29 against the RETARGETED subject set, all invariants isolated
# (the pre-OPS.37 marker was deliberately dropped with the surface it proved — a mutation
# proof over a dead input is the most expensive form of a lying gate):
#   A/shell   literal instead of $VAR in secrets-common      → RED naming file+var+truncated value
#   A/interp  literal instead of the placeholder in COAP_ENV → RED
#   B/global  quintet member added to the GLOBAL env.secret  → RED (the new, sharper half)
#   B/missing quintet member removed from servers.job        → RED naming the member
#   B2        ORACLE_PRIVATE_KEY as a structural key         → RED
#   B3        canopy servers: array → hash                   → RED
#   D ×2      present-empty in COAP_ENV and in env.clear     → RED
#   C/docker  gha-creds-*.json removed from .dockerignore  → RED naming file+pattern
#   C/git     gha-creds-*.json removed from .gitignore     → RED, and with a DIFFERENT cost
#             sentence ("a live WIF credential becomes committable") — the two halves fail
#             for different reasons and must not read alike
#   C/negate  `!gha-creds-run.json` appended to .gitignore → RED naming the negation
#   C/legacy×3 each ORIGINAL pattern removed in turn from .dockerignore → RED naming that
#             pattern (credentials.yml.enc · master.key · credentials/*.key)
# All fourteen reverted byte-identically; the gate was GREEN before and after each.
# ⚠️ The banner date covers the FIRST EIGHT rows only. 🔴 And this summary stood MID-TABLE
# saying "eleven" while three more rows sat below it, because the legacy trio was appended
# after it — head corrected, tail left asserting the old count, in a file whose entire subject
# is drift. Caught by adversarial review: a mutation table is prose, and nothing counts its rows.
# ⊕ Every C row is dated 2026-09-01 and they are the FIRST this invariant ever had: C shipped
# with no mutation proof at all, so its green had never been shown to be discriminating on ANY
# branch. Adding a member was the occasion, not the reason — the three legacy patterns were
# proved in the same pass rather than left as a documented gap, which would have been a
# self-negating note in a file whose whole subject is drift.
#
# ⊕ B4 entered THIS RECORD on 2026-08-31, and the gap is the instructive part: the check was
# implemented (below) and cited by name from the tracker, but appeared in neither the roster
# above nor the table — i.e. what lagged was the gate's own SELF-DESCRIPTION, which no gate
# can see. A reader following the tracker to "invariant B4" found the label only by luck.
# Mutated on both branches that day:
#   B4/fallback  secrets.canopy REDIS_URL → ${REDIS_URL}        → RED naming file + value
#   B4/absent    the REDIS_URL line deleted outright            → RED naming the inheritance
# Both reverted byte-identically (`git diff --quiet`); GREEN before and after.
# ⊕ B4 widened to the RPC quartet 2026-09-02 [INF.27 move (2)] and mutated the same day, on
# the NEW members rather than on Redis again (a proof on the old member says nothing about
# the loop that now judges five):
#   B4/rpc-absent   the SOLANA_RPC_URL remap deleted outright        → RED naming the inheritance
#   B4/rpc-fallback CELO_RPC_URL rewritten to ${CELO_RPC_URL}       → RED naming file + value
# Both restored byte-identically (`cmp`); GREEN before and after.
# ⊕ 2026-09-02 (second pass, after the first canopy boot): B4's accepted FORM changed and B5 was
# born, both mutated on the live files:
#   B5/bare-default  REDIS_URL restored to ${CANOPY_REDIS_URL:-…}          → RED naming B5
#   A/literal-printf RAILS_MASTER_KEY → $(printf '%s' "deadbeef")           → RED naming A (LOUD_REF admits markers and master.key only)
#   B4/rpc-absent    SOLANA_RPC_URL remap deleted (re-run on the new form) → RED naming the inheritance
# All restored byte-identically (`cmp`); GREEN before and after.
# SUBJECT_FLOOR proved itself organically the same day: a z-after-(.*) parser bug collapsed the
# set to 0 and the floor, not a human, caught the would-be green over an empty set.

require "yaml"

KAMAL_BASE   = "config/deploy.yml"
KAMAL_CANOPY = "config/deploy.canopy.yml"
SECRETS_FILE = ".kamal/secrets-common"
# Destination overlay: Kamal reads secrets-common + secrets.<dest>, dest wins.
# Carries canopy's Redis isolation (REDIS_URL ← $CANOPY_REDIS_URL) — see B4.
SECRETS_CANOPY = ".kamal/secrets.canopy"
ANCHOR_TF    = "terraform/compute.tf" # COAP_ENV heredoc — the anchor daemon's env surface

# Secret-bearing var-name suffixes. `_SECRET` subsumes `_HMAC_SECRET`/`_WEBHOOK_SECRET`;
# `_BASE64` catches base64-wrapped keys; `_RPC_URL`/`REDIS_URL` embed provider keys /
# passwords in the URL; `_TOKEN`/`_API_KEY` cover Grafana/service tokens.
SECRET_NAME = /(_KEY|_KEYPAIR|SECRET_KEY_BASE|_SECRET|_PASSWORD|_TOKEN|_BASE64|_DSN|_RPC_URL|REDIS_URL|_DERIVATION_SALT)\z/
PLACEHOLDER = "REQUIRED_SECRET_NOT_SET"
SHELL_REF   = /\A\$\{?[A-Z][A-Z0-9_]*/  # $VAR / ${VAR} — NOT bare ${VAR:-default}, see B5
# The ONLY command-substitution form invariant A accepts: a real-shell evaluation of a bash
# default whose fallback is a loud marker or the gitignored master.key file — never a literal.
LOUD_REF    = /\A\$\(printf '%s' "\\\$\{[A-Z][A-Z0-9_]*:-(?:[A-Z][A-Z0-9_]*_NOT_SET|\$\(cat config\/master\.key 2>\/dev\/null\))\}"\)\z/
# B5 — bash default/alternate syntax outside a `$( )`: Dotenv reads `${NAME` and leaves the
# rest as literal text, so the container gets `<value>:-…}` (measured on the first canopy boot).
DOTENV_MANGLED = /(?<!\\)\$\{[A-Z][A-Z0-9_]*:[-=+?]/
INTERP      = /\A\$\{[^}]+\}\z/         # ${terraform.interpolation} / "${RELEASE_VERSION}"

# Measured 2026-08-29: 25 in .kamal/secrets-common + 6 in the COAP_ENV heredoc = 31.
# ⊕ Pattern broadened the same day (15 suffixes → 11): the generic `_KEY` subsumes four
# narrower ones and caught TURBO_SIGNED_STREAM_KEY, which none of them matched. Zero false
# positives on the live tree — a var named `*_KEY` on an env surface is a secret by name.
# A parse that breaks returns [] and the gate prints ✓ — so assert the set is still there.
SUBJECT_FLOOR = 20

SIGNING_QUINTET = %w[
  ORACLE_CELO_PRIVATE_KEY ORACLE_MINTER_PRIVATE_KEY
  ORACLE_SLASHER_PRIVATE_KEY ETHEREUM_ANCHOR_PRIVATE_KEY SOLANA_WALLET_KEYPAIR
].freeze

RETIRED_NAME = "ORACLE_PRIVATE_KEY"

failures = []
secret_subjects = 0

# --- readers -----------------------------------------------------------------

# → [[scope_label, clear_hash, secret_names], ...] for every env block a Kamal config declares.
def env_blocks(cfg)
  blocks = [ [ "env", cfg.dig("env", "clear") || {}, Array(cfg.dig("env", "secret")) ] ]
  # servers.web is the ARRAY form (bare host list, no env); job/coap are hashes.
  servers = cfg["servers"]
  servers.each { |role, spec| blocks << [ "servers.#{role}", spec.dig("env", "clear") || {}, Array(spec.dig("env", "secret")) ] if spec.is_a?(Hash) } if servers.is_a?(Hash)
  (cfg["accessories"] || {}).each { |name, spec| blocks << [ "accessories.#{name}", spec.dig("env", "clear") || {}, Array(spec.dig("env", "secret")) ] if spec.is_a?(Hash) }
  blocks
end

def dotenv_pairs(text)
  text.lines.filter_map do |l|
    m = l.chomp.match(/\A\s*([A-Z][A-Z0-9_]*)=(.*)\z/) or next
    [ m[1], m[2].strip ]
  end
end

# Grammar lifted verbatim from spec/deploy/anchor_coap_env_spec.rb — one heredoc, one parser.
def anchor_coap_pairs
  lines  = File.read(ANCHOR_TF).lines
  start  = lines.index { |l| l.include?("<< 'COAP_ENV'") } or raise "coap.env heredoc start not found"
  length = lines[(start + 1)..].index { |l| l.strip == "COAP_ENV" } or raise "coap.env heredoc end not found"
  dotenv_pairs(lines[start + 1, length].join)
end

# --- YAML surfaces (config/deploy.yml + canopy) -------------------------------

configs = { KAMAL_BASE => YAML.safe_load_file(KAMAL_BASE), KAMAL_CANOPY => YAML.safe_load_file(KAMAL_CANOPY) }

configs.each do |file, cfg|
  env_blocks(cfg).each do |scope, clear, secret_names|
    clear.each do |var, value|
      str = value.to_s
      # A — a secret-named var in a CLEAR block must not carry a real value.
      if var.to_s =~ SECRET_NAME && !(str == PLACEHOLDER || str =~ INTERP || str.strip.empty?)
        failures << "#{file}: #{scope}.clear.#{var} carries a non-placeholder literal '#{str[0, 12]}…' — secret vars must be #{PLACEHOLDER} / ${var}"
      end
      # D — present-but-empty.
      failures << "#{file}: #{scope}.clear.#{var} is present-but-empty — B1 silences autodetect/derive; omit the key or give it a value" if value.nil? || str.strip.empty?
    end

    # B2 — retired name as a structural key.
    failures << "#{file}: retired #{RETIRED_NAME} in #{scope} — INF.22 retired it; use the dedicated keys" if clear.key?(RETIRED_NAME) || secret_names.include?(RETIRED_NAME)

    # B — quintet allow-list: only servers.job may carry it. Global env.secret is inherited by
    # EVERY role, so it is the widest leak of all and is judged here too.
    next if scope == "servers.job"

    leaked = SIGNING_QUINTET & secret_names
    failures << "#{file}: signing quintet #{leaked} in #{scope} — must be servers.job ONLY (global env.secret is inherited by every role, coap included)" if leaked.any?
  end
end

# B — the completeness half, base config only (canopy is web-only by B3).
job_secrets = Array(configs[KAMAL_BASE].dig("servers", "job", "env", "secret"))
missing = SIGNING_QUINTET - job_secrets
failures << "#{KAMAL_BASE}: signing quintet missing from servers.job env.secret: #{missing}" if missing.any?

# B3 — canopy stays the array form (deep_merge REPLACES arrays, UNIONS hash keys).
unless configs[KAMAL_CANOPY]["servers"].is_a?(Array)
  failures << "#{KAMAL_CANOPY}: `servers:` must stay the ARRAY form — a hash is deep_merged as a keys-UNION, silently inheriting the base `job` role (money quintet) into a leg whose secrets are production-scoped → present-empty inject → Web3NetworkGuard raise"
end

# --- text surfaces (.kamal/secrets-common + secrets.canopy + anchor COAP_ENV) --

[ [ SECRETS_FILE,   dotenv_pairs(File.read(SECRETS_FILE)),   :shell ],
  [ SECRETS_CANOPY, dotenv_pairs(File.read(SECRETS_CANOPY)), :shell ],
  [ ANCHOR_TF,      anchor_coap_pairs,                       :interp ] ].each do |file, pairs, form|
  pairs.each do |var, value|
    # D — present-but-empty (both forms).
    if value.empty?
      failures << "#{file}: #{var}= is present-but-empty — B1 silences autodetect/derive; omit the line or give it a value"
      next
    end
    # B5 — bare bash default syntax is not Dotenv (both shell-form files are parsed by Kamal::Secrets).
    failures << "#{file}: #{var} uses bare ${…:-…} — Kamal's Dotenv parser delivers '<value>:-…}'; write $(printf '%s' \"\\${VAR:-MARKER}\") (spec/deploy/kamal_secrets_parse_spec.rb)" if form == :shell && value =~ DOTENV_MANGLED
    # B2 — retired name as a structural key (never a grep: the name appears in prose here).
    failures << "#{file}: retired #{RETIRED_NAME} declared — INF.22 retired it; use the dedicated keys" if var == RETIRED_NAME
    next unless var =~ SECRET_NAME

    secret_subjects += 1
    ok = form == :shell ? (value =~ SHELL_REF || value =~ LOUD_REF) : (value == PLACEHOLDER || value =~ INTERP)
    expected = form == :shell ? "a shell reference ($VAR) or the loud form $(printf '%s' \"\\${VAR:-MARKER_NOT_SET}\")" : "#{PLACEHOLDER} / ${terraform interpolation}"
    failures << "#{file}: #{var} carries a non-reference literal '#{value[0, 12]}…' — must be #{expected}" unless ok
  end
end

# Lantern on our own subject set — a broken text parse returns [] and prints ✓ otherwise.
failures << "subject set collapsed: #{secret_subjects} secret-named vars scanned, floor is #{SUBJECT_FLOOR} — the parser, not the tree, is the likely change" if secret_subjects < SUBJECT_FLOOR

# B4 — canopy isolation is STRUCTURAL, not CI-only. Every shared external resource the base
# secrets-common names (production Redis; the four mainnet RPCs) must be remapped here from its
# CANOPY_* twin with the loud placeholder fallback — never a silent fall-through to the base
# name, which would put staging on production Redis / a mainnet endpoint exactly on the local
# `kamal deploy -d canopy` path DEPLOY-DAY Phase 3 names. The four RPC names are the guard's
# `RPC_URL_ENVS` [INF.27 move (2)]; the list is spelled out rather than read from the guard so
# this stdlib script stays Rails-free — a divergence reds `web3_env_loudness_spec`, not here.
CANOPY_REMAPS = %w[REDIS_URL ALCHEMY_POLYGON_RPC_URL ALCHEMY_ETHEREUM_RPC_URL SOLANA_RPC_URL CELO_RPC_URL].freeze
canopy_pairs = dotenv_pairs(File.read(SECRETS_CANOPY)).to_h
CANOPY_REMAPS.each do |name|
  value = canopy_pairs[name]
  if value.nil?
    failures << "#{SECRETS_CANOPY}: no #{name} remap — canopy inherits secrets-common's $#{name} (the PRODUCTION value) on a local destination run"
  elsif value !~ /\$\{?CANOPY_#{name}\b/ || value =~ /\$\{?#{name}\b/
    failures << "#{SECRETS_CANOPY}: #{name} must reference $CANOPY_#{name} and never fall back to $#{name} (got '#{value[0, 40]}')"
  end
end

# --- C: .dockerignore --------------------------------------------------------

# Invariant C — the two IGNORE files keep secret material out of the two places it must never
# reach: the PUBLIC GHCR image and the PUBLIC git history.
#   .dockerignore — a leaked RAILS_MASTER_KEY would decrypt a shipped credentials.yml.enc.
#   .gitignore    — `gha-creds-*.json` is the LIVE WIF credential that
#                   `google-github-actions/auth` writes INTO the workspace (measured run
#                   33499357498, where it made the checkout dirty and pre-build aborted).
# 🔴 BOTH files are judged, and that is the whole point of the pair: the docker build context
# IS the workspace, so `.gitignore` stops the COMMIT and `.dockerignore` stops the IMAGE, and
# neither implies the other (the commit that added them says exactly this). Gating only one
# leaves the other a rule with no carrier — which is what it was until 2026-09-01.
DOCKERIGNORE_MUST = [
  "config/credentials.yml.enc", "config/master.key", "config/credentials/*.key",
  # ⚠️ No leading slash in the live file, and the matcher below strips at most ONE — so this
  # entry matches `gha-creds-*.json` as written AND a future `/gha-creds-*.json`.
  "gha-creds-*.json"
].freeze
GITIGNORE_MUST = [ "gha-creds-*.json" ].freeze
{ ".dockerignore" => DOCKERIGNORE_MUST, ".gitignore" => GITIGNORE_MUST }.each do |file, must|
  unless File.exist?(file)
    failures << "#{file} is missing entirely"
    next
  end
  lines = File.read(file).lines.map(&:strip)
  must.each do |pat|
    excluded = lines.any? { |l| !l.start_with?("!") && l.sub(%r{\A/}, "") == pat }
    failures << "#{file}: no exclusion for #{pat} — " \
                "#{file == '.gitignore' ? 'a live WIF credential becomes committable' : 'would ship into the public image'}" unless excluded
  end
  negated = lines.select { |l| l.start_with?("!") && l.match?(/credential|master\.key|\.enc|gha-creds/i) }
  failures << "#{file}: a negation re-includes a secret file: #{negated}" if negated.any?
end

if failures.empty?
  puts "✓ Deploy-secret scan: #{secret_subjects} secret-named vars carry references only; quintet job-only (global env.secret clean); canopy array-form intact; canopy overlay remaps all #{CANOPY_REMAPS.size} shared resources"
else
  puts "DEPLOY-SECRET SCAN FAILED:"
  failures.each { |f| puts "  ✗ #{f}" }
  exit 1
end
