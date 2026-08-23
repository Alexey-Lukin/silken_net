# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [SEC.22] Refuse to boot production / canopy without ActiveRecord Encryption keys.
#
# The three keys decrypt `hardware_keys` (device AES / Lorenz-seed columns) and
# `users.otp_secret` (the TOTP seed). They live in ENV, never
# credentials.yml.enc — see config/environments/production.rb and docs/06_04 §5.7.
# Without them, non-deterministic `encrypts` raises Configuration at the first
# encrypt/decrypt, so provisioning + telemetry-decrypt + MFA are dead-on-first-use
# rather than failing loudly up front. The content judgement lives in
# `Security::EncryptionKeyGuard` (unit-tested); this initializer only decides WHEN
# to enforce + how to bypass — mirroring master_key_strength_check.rb.
#
# NOT process-scoped (contrast web3_network_guard's signer_process:): the web
# containers (provisioning / m2m / MFA) and the Sidekiq workers (telemetry unpack,
# OTA, key rotation) both decrypt AR-encrypted columns, so every process that boots
# the full app needs the keys. (The coap daemon only enqueues and never decrypts,
# but these are narrow column-scoped keys — not the vault key — so a uniform check
# is simpler than scoping it out.)

Rails.application.config.after_initialize do
  # Canopy uses the same RAILS_ENV=production as mainnet; both are gated here.
  next unless Rails.env.production?

  # Dockerfile `assets:precompile` boots production with no secrets on purpose;
  # the runtime boot (no dummy flag) still enforces this.
  next if ENV["SECRET_KEY_BASE_DUMMY"].present?

  if ENV["SILKENNET_SKIP_AR_ENCRYPTION_KEYS_CHECK"] == "1"
    # Loud on purpose — a bypassed boot-time crypto check must leave a trail so the
    # rescue-boot escape hatch cannot quietly become routine.
    Rails.logger.warn(
      "[SEC.22] ActiveRecord Encryption keys check BYPASSED via " \
      "SILKENNET_SKIP_AR_ENCRYPTION_KEYS_CHECK=1 — intended only for a one-off rescue " \
      "boot. Unset it for normal operation."
    )
    next
  end

  violations = Security::EncryptionKeyGuard.violations(ENV)
  next if violations.empty?

  raise SecurityError,
        "[SEC.22] Refusing to boot (RAILS_ENV=#{Rails.env}) — ActiveRecord Encryption:\n  " +
        violations.join("\n  ") +
        "\nGenerate via `bin/rails db:encryption:init` (or SecureRandom.alphanumeric(32)) " \
        "and inject as ENV on web + job. See docs/06_04 §5.7 and docs/00_07 SEC.22. " \
        "For a deliberate rescue boot, set SILKENNET_SKIP_AR_ENCRYPTION_KEYS_CHECK=1."
end
