# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Refuse to boot a strict/mainnet deployment with unsafe Web3 wiring:
# a TESTNET RPC URL (mints real value on a throwaway chain), a missing/malformed
# oracle signer key (KeyError → silent Sidekiq DeadSet), or a broken DAO-treasury
# address (its read-sites rescue everything → the 2% Dynamic Tax silently stays
# off). The content judgement lives in `Security::Web3NetworkGuard` (unit-tested);
# this initializer only decides WHEN to enforce + how to bypass — mirroring
# `config/initializers/master_key_strength_check.rb`.

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

  raise SecurityError,
        "Refusing to boot (RAILS_ENV=#{Rails.env}, " \
        "WEB3_STRICT_MODE=#{ENV['WEB3_STRICT_MODE'].inspect}):\n  " +
        violations.join("\n  ") +
        "\nSee docs/06_04 (Web3 deploy secrets). For a deliberate rescue boot, " \
        "set SILKENNET_SKIP_WEB3_NETWORK_GUARD=1."
end
