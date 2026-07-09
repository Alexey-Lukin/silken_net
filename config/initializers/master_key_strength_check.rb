# frozen_string_literal: true

# [SEC.9] Refuse to boot production / canopy with a weak PROVISIONING_MASTER_KEY.
#
# The master key feeds HKDF for both `HardwareKeyService` (AES-256 device key)
# and `OtaHmacKeyService` (K_ota). If it matches a publicly-known test vector
# (FIPS-197, NIST SP 800-38A, RFC 3686 / 4231) or a degenerate / placeholder
# pattern, the entire downstream key tree collapses — SEC.9 in
# `docs/00_07_Action_Plan_Tracker.md` and §3.1а of `docs/03_05` document the
# original BLOCKER (firmware key sharing first 16 bytes with the FIPS-197
# Appendix B test vector).
#
# Behaviour
# ---------
# * Production / canopy: raise on missing OR weak master key — fail fast at
#   boot instead of silently deriving compromised child keys.
# * Asset build: skip when `SECRET_KEY_BASE_DUMMY` is set — the Dockerfile's
#   `assets:precompile` boots production without secrets on purpose; the runtime
#   boot (no dummy flag) still enforces the check.
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

  # Build-time asset compilation (`SECRET_KEY_BASE_DUMMY=1 ./bin/rails
  # assets:precompile` in the Dockerfile) boots the production environment with
  # no real secrets injected — by design, PROVISIONING_MASTER_KEY must never be
  # baked into the image. Honour Rails' own dummy-boot signal and skip here; the
  # runtime boot (no SECRET_KEY_BASE_DUMMY) still enforces the check before the
  # app accepts traffic.
  next if ENV["SECRET_KEY_BASE_DUMMY"].present?

  # The CoAP intake daemon (lib/daemons/coap_listener) is pure UDP glue: it
  # receives datagrams and perform_async's them to UnpackTelemetryWorker. All key
  # derivation (HardwareKeyService, OtaHmacKeyService) happens in the Sidekiq
  # workers (OTA) and the provisioning web path — never in this process. So it
  # needs no PROVISIONING_MASTER_KEY; let it boot without the HKDF crown-jewel,
  # keeping the fleet-wide-forge root off the coap container's plaintext
  # /proc/environ (SEC.22). Mirrors web3_network_guard's process-scoping
  # (signer_process: Sidekiq.server?).
  next if $PROGRAM_NAME.include?("coap_listener")

  if ENV["SILKENNET_SKIP_MASTER_KEY_STRENGTH_CHECK"] == "1"
    # [SEC.9] Loud on purpose — a bypassed boot-time crypto strength check must
    # leave a trail so the rescue-boot escape hatch cannot quietly become routine.
    Rails.logger.warn(
      "[SEC.9] PROVISIONING_MASTER_KEY strength check BYPASSED via " \
      "SILKENNET_SKIP_MASTER_KEY_STRENGTH_CHECK=1 — intended only for one-off rescue " \
      "boots while re-flashing a stuck cluster. Unset it for normal operation."
    )
    next
  end

  master_key = ENV["PROVISIONING_MASTER_KEY"]
  hint       = "PROVISIONING_MASTER_KEY"

  if master_key.blank?
    raise SecurityError,
          "[SEC.9] #{hint} is not set. HardwareKeyService and OtaHmacKeyService " \
          "both require it to derive device keys via HKDF. See docs/03_06 §2 " \
          "and docs/00_07 SEC.9."
  end

  if (reason = Security::WeakKeyDetector.detect(master_key, hint: hint))
    raise SecurityError,
          "[SEC.9] Refusing to boot: master key is weak — #{reason}. " \
          "Generate a fresh value via `SecureRandom.hex(32)` (or hardware RNG) " \
          "and store it in the secrets vault. See docs/03_05 §3.1а and " \
          "docs/00_07 SEC.9 for the full rotation runbook."
  end
end
