# frozen_string_literal: true

# [SEC.9] Refuse to boot production / canopy with a weak PROVISIONING_MASTER_KEY.
#
# The master key feeds HKDF for both `HardwareKeyService` (AES-256 device key)
# and `OtaHmacKeyService` (K_ota). If it matches a publicly-known test vector
# (FIPS-197, NIST SP 800-38A, RFC 3686 / 4231) or a degenerate / placeholder
# pattern, the entire downstream key tree collapses — SEC.9 in
# `docs/10_02_Action_Plan_Tracker.md` and §3.1 of `docs/03_05` document the
# original BLOCKER (firmware key sharing first 16 bytes with the FIPS-197
# Appendix B test vector).
#
# Behaviour
# ---------
# * Production / canopy: raise on missing OR weak master key — fail fast at
#   boot instead of silently deriving compromised child keys.
# * Test / development: skip entirely. `spec/rails_helper.rb` pins a stable
#   non-secret fixture (`silken-net-test-master-key-32b!!`) — guarding here
#   would make the whole suite refuse to load, which is not the threat
#   model we are trying to defend against.
# * Override: set `SILKENNET_SKIP_MASTER_KEY_STRENGTH_CHECK=1` to bypass.
#   Intended for one-off rescue boots when re-flashing a stuck cluster —
#   the bypass is loud (warning log) so it cannot become routine.

Rails.application.config.after_initialize do
  # Canopy uses the same RAILS_ENV=production as mainnet; both are gated here.
  next unless Rails.env.production?
  next if ENV["SILKENNET_SKIP_MASTER_KEY_STRENGTH_CHECK"] == "1"

  master_key = ENV["PROVISIONING_MASTER_KEY"]
  hint       = "PROVISIONING_MASTER_KEY"

  if master_key.blank?
    raise SecurityError,
          "[SEC.9] #{hint} is not set. HardwareKeyService and OtaHmacKeyService " \
          "both require it to derive device keys via HKDF. See docs/03_05 §3.4а " \
          "and docs/10_02 SEC.9."
  end

  if (reason = Security::WeakKeyDetector.detect(master_key, hint: hint))
    raise SecurityError,
          "[SEC.9] Refusing to boot: master key is weak — #{reason}. " \
          "Generate a fresh value via `SecureRandom.hex(32)` (or hardware RNG) " \
          "and store it in the secrets vault. See docs/03_05 §3.1 and " \
          "docs/10_02 SEC.9 for the full rotation runbook."
  end
end
