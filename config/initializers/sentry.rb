# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# = ===================================================================
# 🛡️ SENTRY (Error Tracking & Performance Monitoring)
# = ===================================================================
# Hyper-scale IoT + Web3 configuration optimized for:
# - Cost Control: extreme sampling (0.1% traces) to stay within APM budget
# - Noise Reduction: exhaustive exception exclusion (IoT/Web3 transient errors)
# - Zero-Trust Security: PII disabled, sensitive keys scrubbed
# - Non-blocking: async background workers for event transmission
#
# DSN is read from ENV["SENTRY_DSN"]. When absent (dev/test), Sentry is inert.

Sentry.init do |config|
  config.dsn = ENV["SENTRY_DSN"]

  # -----------------------------------------------------------------------
  # 🌍 ENVIRONMENT & RELEASE
  # -----------------------------------------------------------------------
  # 🎰 [INF.27] SLOT, not `Rails.env`. The DSN is a single shared secret — both slots map the
  # same `SENTRY_DSN` — so `Rails.env` filed every canopy exception into the production
  # project under `environment: production`: inflated issue counts, corrupted "new since
  # release" grouping, and a page for whoever is on prod-call because staging was deployed.
  # Undeclared falls back to `Rails.env`, so dev/test still report themselves honestly.
  config.environment = SilkenNet::DeploymentSlot.current
  # 🔴 RELEASE: read what Kamal INJECTS, never what a manifest promises. Measured on live canopy
  # 2026-09-02: `env.clear` carried `RELEASE_VERSION: "${RELEASE_VERSION}"`, and Kamal passes
  # `env.clear` as `--env KEY=VALUE` inside the `docker run` it executes over SSH — so the
  # REMOTE shell on the app host expanded `${RELEASE_VERSION}` (unset there) to "", Sentry
  # discarded it ("release: expected a non-empty string") and every event shipped release-less
  # while the manifest, both workflows and the canon all said "set by CI". `KAMAL_VERSION` is
  # the git sha Kamal itself puts on every container (`Kamal::Commands::App#run`); `.presence`
  # keeps the present-but-EMPTY class (INF.22/S2.4) from ever reaching the SDK again.
  # `RELEASE_VERSION` remains as the explicit override for non-Kamal processes (anchor daemon).
  config.release     = ENV["RELEASE_VERSION"].presence || ENV["KAMAL_VERSION"].presence

  # -----------------------------------------------------------------------
  # 🔒 DATA SANITIZATION (Zero-Trust Security)
  # -----------------------------------------------------------------------
  # Never send PII (emails, IPs, cookies, user-agent) to Sentry.
  config.send_default_pii = false

  # Scrub AES keys, wallet secrets, mnemonics, and binary payloads.
  # Extends Rails.application.config.filter_parameters automatically via
  # sentry-rails, but we add extra patterns explicitly for defense-in-depth.
  config.before_send = lambda { |event, _hint|
    # Scrub sensitive fields from extra context and breadcrumbs
    scrub_patterns = /aes_key|wallet_private_key|mnemonic|private_key|binary_payload|secret_key/i

    if event.extra.is_a?(Hash)
      event.extra.each_key do |key|
        event.extra[key] = "[FILTERED]" if key.to_s.match?(scrub_patterns)
      end
    end

    # Defense-in-depth: redact secret VALUES that leaked into free text. An
    # accidental `raise "... aes_key=#{hex}"` surfaces in event.exception.values[].value
    # (and Sentry.capture_message in event.message) — which the extra-context scrub above
    # and filter_parameters (request params only) both miss. Redact only the value AFTER a
    # labelled secret, so public hashes (tx / address) stay readable for debugging.
    # `[\w-]*token` catches access_token=/refresh_token= (a bare `token` alt misses them —
    # no word boundary after the underscore).
    secret_value = /\b(aes_key|wallet_private_key|private_key|secret_key|signing_key|api_key|secret|mnemonic|seed|keypair|passw(?:or)?d|[\w-]*token)(["']?\s*[=:]\s*["']?)([^\s"',;)]{2,})/i
    # Inline URL credentials (rediss://user:PWD@host, postgres://user:PWD@host, and the
    # user-less redis://:PWD@host shape — group 1 is `*` not `+`) carry NO label=, so the
    # pattern above misses them; a PG/Redis error or http_logger breadcrumb leaks them raw.
    inline_url_cred = %r{(://[^:/@\s]*:)([^@\s/]{2,})(@)}
    # `Authorization: Bearer <jwt>` / bare `Bearer <token>` — space-separated, no label=.
    # Applied BEFORE secret_value so the "Bearer" label survives while its token is redacted.
    bearer_token = %r{\b(bearer\s+)([A-Za-z0-9._~+/-]{8,}=*)}i
    redact = lambda do |val|
      case val
      when String
        s = val.gsub(bearer_token) { "#{$1}[FILTERED]" }
        s = s.gsub(secret_value) { "#{$1}#{$2}[FILTERED]" }
        s.gsub(inline_url_cred) { "#{$1}[FILTERED]#{$3}" }
      when Hash  then val.transform_values { |v| redact.call(v) }
      when Array then val.map { |v| redact.call(v) }
      else val
      end
    end

    event.try(:exception)&.values&.each { |ex| ex.value = redact.call(ex.value) }
    event.message = redact.call(event.message) if event.respond_to?(:message=) && event.message.present?
    # Breadcrumbs (incl. the :http_logger RPC-URL crumb) were NOT scrubbed despite the
    # comment above — recursively redact each crumb's message + nested data values.
    if event.respond_to?(:breadcrumbs) && event.breadcrumbs.respond_to?(:each)
      event.breadcrumbs.each do |bc|
        bc.message = redact.call(bc.message) if bc.respond_to?(:message=) && bc.message
        bc.data = redact.call(bc.data) if bc.respond_to?(:data=) && bc.data
      end
    end

    event
  }

  # -----------------------------------------------------------------------
  # 🚫 EXHAUSTIVE EXCEPTION EXCLUSION (Zero Noise Policy)
  # -----------------------------------------------------------------------
  # We only want Sentry to alert on actionable, unexpected crashes (5xx).
  # Routine IoT network blips, handled Web3 429s, and standard Rails noise
  # are excluded to prevent alert fatigue and reduce Sentry event volume.
  config.excluded_exceptions += [
    # --- Standard Rails / Rack noise ---
    "ActionController::RoutingError",
    "ActionController::BadRequest",
    "ActionController::UnknownFormat",
    "ActionController::InvalidAuthenticityToken",
    "ActionController::InvalidCrossOriginRequest",
    "ActionController::ParameterMissing",
    "ActionDispatch::Http::Parameters::ParseError",
    "ActiveRecord::RecordNotFound",
    "ActiveRecord::RecordInvalid",
    "ActiveRecord::RecordNotUnique",
    "ActiveRecord::StaleObjectError",

    # --- Authentication / Authorization (expected 401/403) ---
    "Pundit::NotAuthorizedError",

    # --- CoAP / IoT transient errors (retries expected) ---
    "CoapClient::Error",
    "CoapClient::ClientError",
    "CoapClient::ServerError",
    "CoapClient::NetworkError",

    # --- Web3 / Blockchain transient errors (Sidekiq retries handle these) ---
    "Web3::HttpClient::RequestError",
    "HTTPX::TimeoutError",
    "HTTPX::ConnectionError",
    "Net::OpenTimeout",
    "Net::ReadTimeout",
    "Errno::ECONNREFUSED",
    "Errno::ECONNRESET",
    # DB/Redis connection blips: infra-domain (Grafana up-metric alerts), not app
    # crashes — and their exception message carries the URL-with-inline-password
    # (the redact backstop covers it, excluding here also kills the recurring noise).
    "PG::ConnectionBad",
    "RedisClient::CannotConnectError",

    # --- Sidekiq Enterprise rate limiting (auto-rescheduled) ---
    "Sidekiq::Limiter::OverLimit",

    # --- Domain-specific handled errors (logged, not crash-worthy) ---
    "HardwareKeyService::RotationPendingError",
    "BioContractFirmware::IntegrityError",
    "Dclimate::VerificationService::OrbitalLagError",
    "Polygon::HadronComplianceService::ComplianceError",
    "KlimaDao::RetirementService::InsufficientBalanceError",
    "KlimaDao::RetirementService::InvalidTokenTypeError",
    "Peaq::DidRegistryService::RegistrationError",
    "Chainlink::OracleDispatchService::DispatchError",
    "Iotex::W3bstreamVerificationService::VerificationError",
    "TheGraph::QueryService::QueryError",
    "Ed25519Crypto::SigningService::SigningError"
  ]

  # -----------------------------------------------------------------------
  # 📊 PERFORMANCE SAMPLING (Extreme Scale Budget Control)
  # -----------------------------------------------------------------------
  # With millions of Sidekiq jobs and CoAP packets per day, sending 100%
  # of performance traces would blow any APM budget. 0.1% captures enough
  # statistical data to spot slow Web3 RPC calls and telemetry bottlenecks.
  config.traces_sample_rate = Float(ENV.fetch("SENTRY_TRACES_SAMPLE_RATE", "0.001"))

  # -----------------------------------------------------------------------
  # ⚡ ASYNC EVENT TRANSMISSION (Non-blocking)
  # -----------------------------------------------------------------------
  # Sentry uses background threads for event delivery so it never blocks
  # Puma request threads or Sidekiq job processors. 2 threads is sufficient
  # for our volume given the aggressive sampling above.
  config.background_worker_threads = Integer(ENV.fetch("SENTRY_WORKER_THREADS", "2"))

  # -----------------------------------------------------------------------
  # 🧹 BREADCRUMB CLEANUP
  # -----------------------------------------------------------------------
  # Limit breadcrumbs to reduce payload size per event. IoT telemetry
  # pipelines can generate hundreds of breadcrumbs in a single job.
  config.breadcrumbs_logger = [ :active_support_logger, :http_logger ]
  config.max_breadcrumbs = 30
end
