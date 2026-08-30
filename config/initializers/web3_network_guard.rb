# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Refuse to boot a strict deployment with unsafe Web3 wiring: an RPC URL on the wrong
# chain family (mainnet value minted on a throwaway chain, or staging able to sign real
# transactions), a missing/malformed oracle signer key (KeyError → silent Sidekiq
# DeadSet), or a broken DAO-treasury address (its read-sites rescue everything → the 2%
# Dynamic Tax silently stays off). The content judgement lives in
# `Security::Web3NetworkGuard` (unit-tested); this initializer only decides WHEN to
# enforce + how to bypass — mirroring `config/initializers/master_key_strength_check.rb`.
#
# 🔑 Two axes, deliberately NOT merged [OPS.37]. This gate is the "hardened runtime" half
# and stays keyed on `Rails.env.production? ∨ WEB3_STRICT_MODE` — a staging slot wants it
# ON. Which chain the slot may touch is the OTHER half, declared per slot in
# `WEB3_CHAIN_ENV` and judged inside the guard. Reading `Rails.env` as an answer to the
# second question is the conflation this split exists to remove.

Rails.application.config.after_initialize do
  # Enforce in production/canopy, or anywhere WEB3_STRICT_MODE=true (the same
  # gate IoTeX / Hadron fail-closed under).
  next unless Rails.env.production? || ENV["WEB3_STRICT_MODE"] == "true"

  # Dockerfile `assets:precompile` boots production with no secrets on purpose;
  # the runtime boot (no dummy flag) still enforces this.
  next if ENV["SECRET_KEY_BASE_DUMMY"].present?

  if ENV["SILKENNET_SKIP_WEB3_NETWORK_GUARD"] == "1"
    # Loud on purpose — a bypassed boot-time safety check must leave a trail so
    # the rescue-boot escape hatch cannot quietly become routine.
    Rails.logger.warn(
      "Web3 network guard BYPASSED via SILKENNET_SKIP_WEB3_NETWORK_GUARD=1 — " \
      "intended only for a one-off rescue boot. Unset it for normal operation."
    )
    next
  end

  # Key-PRESENCE is demanded only where keys are consumed: the Sidekiq signer
  # process. The web/coap containers boot keyless by design (plaintext-ENV
  # exposure) — a missing key still fails loudly, at job-boot, before any DeadSet.
  violations = Security::Web3NetworkGuard.violations(ENV, signer_process: Sidekiq.server?)
  next if violations.empty?

  # All three are echoed because they are the THREE separate questions this boot asks:
  # which runtime, which enforcement arm armed the guard, and which chain family this slot
  # claims. A `[chain]` violation is unreadable without the third — it is half the assertion.
  raise SecurityError,
        "Refusing to boot (RAILS_ENV=#{Rails.env}, " \
        "WEB3_STRICT_MODE=#{ENV['WEB3_STRICT_MODE'].inspect}, " \
        "#{Security::Web3NetworkGuard::CHAIN_ENV_VAR}=" \
        "#{Security::Web3NetworkGuard.chain_env(ENV).inspect}):\n  " +
        violations.join("\n  ") +
        "\nSee docs/06_04 (Web3 deploy secrets). For a deliberate rescue boot, " \
        "set SILKENNET_SKIP_WEB3_NETWORK_GUARD=1."
end
