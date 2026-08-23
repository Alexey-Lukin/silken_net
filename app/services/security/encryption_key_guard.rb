# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Pure content-judge for ActiveRecord Encryption keys. Mirrors
# `Security::Web3NetworkGuard` / `Security::WeakKeyDetector`: `.violations(env)`
# returns an array of human-readable strings (empty = safe); the companion
# initializer (`config/initializers/active_record_encryption_keys_check.rb`)
# decides WHEN to enforce (production) and raises `SecurityError`.
#
# The three keys (primary / deterministic / key-derivation-salt) decrypt the
# `hardware_keys` device-key columns and the `users.otp_secret` TOTP column.
# [SEC.22] They come from ENV, never credentials.yml.enc — putting them in the
# vault would deepen the runtime RAILS_MASTER_KEY dependency we are dissolving.
# A blank key does NOT silently fall through to plaintext: non-deterministic
# `encrypts` with a nil key raises Configuration at the first encrypt/decrypt, so
# provisioning + telemetry-decrypt + MFA would be dead-on-first-use. Catch it at
# boot instead.
module Security
  module EncryptionKeyGuard
    module_function

    REQUIRED_ENVS = %w[
      ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY
      ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY
      ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT
    ].freeze

    # Rails `db:encryption:init` emits 32-char keys; the dev/test fixtures are 32.
    MIN_LENGTH = 32

    # `env` defaults to ENV but is injectable for tests.
    def violations(env = ENV)
      REQUIRED_ENVS.filter_map do |var|
        value = env[var]
        if value.blank?
          "[ar-encryption] #{var} is not set — HardwareKey provisioning, telemetry " \
            "decrypt and TOTP secret read/write all raise without it."
        elsif value.length < MIN_LENGTH
          "[ar-encryption] #{var} is #{value.length} chars — need at least #{MIN_LENGTH}."
        elsif (reason = Security::WeakKeyDetector.detect(value, hint: var))
          "[ar-encryption] #{reason}"
        end
      end
    end
  end
end
