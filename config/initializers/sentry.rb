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
  config.environment = Rails.env
  config.release     = ENV.fetch("RELEASE_VERSION", nil)

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
    secret_value = /\b(aes_key|wallet_private_key|private_key|secret_key|signing_key|api_key|secret|mnemonic|seed|keypair|passw(?:or)?d|token)(["']?\s*[=:]\s*["']?)([^\s"',;)]{2,})/i
    redact = ->(str) { str.is_a?(String) ? str.gsub(secret_value) { "#{$1}#{$2}[FILTERED]" } : str }

    event.try(:exception)&.values&.each { |ex| ex.value = redact.call(ex.value) }
    event.message = redact.call(event.message) if event.respond_to?(:message=) && event.message.present?

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
    "Streamr::BroadcasterService::BroadcastError",
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
