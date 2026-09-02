# SPDX-License-Identifier: AGPL-3.0-or-later
require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Active Storage: S3 primary + GCS mirror for disaster recovery at scale.
  # Writes go to both services simultaneously; reads come from S3.
  # ⚖️ [2026-09-02] Overridable per slot: canopy runs `local` (Disk inside the container,
  # ephemeral — staging carries no storage credentials at all, and with `production_mirror`
  # the AWS SDK fell through to EC2 instance-profile lookup on a GCP VM and printed an
  # `Error retrieving instance profile credentials: HTTP 404` on every boot). Default keeps
  # production on the mirror; the name must exist in config/storage.yml (06_04 §2.1).
  config.active_storage.service = ENV.fetch("ACTIVE_STORAGE_SERVICE", "production_mirror").to_sym

  # VIPS is 10-20x faster than MiniMagick for variant generation (critical at scale).
  # Requires libvips system library (already in Dockerfile base image).
  config.active_storage.variant_processor = :vips

  # Queue variant generation as background jobs — never block the request cycle.
  config.active_storage.resolve_model_to_route = :rails_storage_proxy

  # [PROD] Assume all access to the app is happening through an SSL-terminating reverse proxy
  # (Kamal proxy, GCP Load Balancer, Cloudflare). This makes Rails treat upstream HTTP
  # requests as HTTPS and emit secure cookies/links accordingly. Override with DISABLE_SSL=true
  # only for non-TLS canary deployments.
  config.assume_ssl = ENV["DISABLE_SSL"] != "true"

  # Internal probe paths (health checks + Prometheus scrape) reach the app over HTTP by IP
  # with no Host header — excluded from BOTH the SSL redirect and host-authorization below.
  # Single-sourced so the two exclusions can never drift: a renamed/added probe touched in
  # one place but not the other would silently break the deploy health-check behind a green
  # boot. Keep in sync with config.silence_healthcheck_path (/up) + Kamal proxy.healthcheck.
  probe_paths   = %w[/up /ready /metrics].freeze
  probe_request = ->(request) { probe_paths.include?(request.path) }

  # [PROD] Force all access to the app over SSL, enable HSTS (1 year + subdomains + preload),
  # and use secure cookies. Health checks (/up, /ready) and Prometheus scrape (/metrics) are excluded so
  # internal probes that hit HTTP directly continue to work.
  config.force_ssl = ENV["DISABLE_SSL"] != "true"
  config.ssl_options = {
    redirect: { exclude: probe_request },
    hsts:     { expires: 1.year, subdomains: true, preload: true }
  }

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]

  # [S2.5] Structured JSON logging for production.
  # JSON format enables Cloud Logging parsing, Sentry correlation, and Grafana Loki queries.
  # Oj (already in Gemfile) provides fast JSON serialization.
  # Compatible with Cloud Logging cost exclusion (severity field used for filtering).
  if ENV["RAILS_LOG_JSON"] != "false"
    json_logger = ActiveSupport::Logger.new(STDOUT)
    current_pid = Process.pid
    # 🎰 [INF.27] `service` is constant across both deploys and `severity`/`pid` say nothing
    # about origin — so until this field existed, canopy and production log lines were
    # INDISTINGUISHABLE in Cloud Logging / Loki. Hoisted out of the proc like `pid`: the slot
    # cannot change inside a process, and re-reading ENV per log line is a hot-path cost.
    current_slot = SilkenNet::DeploymentSlot.current
    json_logger.formatter = proc do |severity, timestamp, progname, msg|
      payload = {
        severity: severity,
        timestamp: timestamp.utc.iso8601(3),
        message: msg.is_a?(String) ? msg : msg.inspect,
        service: "silken_net",
        slot: current_slot,
        pid: current_pid
      }
      # Sentry trace correlation (if available)
      if defined?(Sentry) && (scope = Sentry.get_current_scope)
        span = scope.get_span
        if span
          payload[:sentry_trace_id] = span.trace_id
          payload[:sentry_span_id] = span.span_id
        end
      end
      Oj.dump(payload, mode: :compat) + "\n"
    end
    config.logger = ActiveSupport::TaggedLogging.new(json_logger)
  else
    config.logger = ActiveSupport::TaggedLogging.logger(STDOUT)
  end

  # [COST CONTROL]: Default to "warn" in production to avoid massive Cloud Logging bills.
  # INFO-level logs from millions of telemetry events can cost more than the infrastructure.
  # Override with RAILS_LOG_LEVEL=info only for debugging sessions.
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "warn")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Replace the default in-process memory cache store with a durable alternative.
  config.cache_store = :solid_cache_store

  # All 32 domain workers already use Sidekiq directly (include Sidekiq::Job).
  # Route ActiveJob (mailer deliver_later, etc.) through Sidekiq as well,
  # so all background processing is unified on a single Redis-backed engine.
  # This avoids running an idle Solid Queue supervisor inside Puma.
  config.active_job.queue_adapter = :sidekiq

  # `raise_delivery_errors` is left at the Rails default (`true`, measured) so a
  # refused SMTP connection surfaces as a failed Sidekiq job instead of a silent
  # no-op. The scaffold comment that used to sit here suggested setting it to
  # `false` — on this platform that would hide exactly the failure ARCH.60 is about.

  # Set host to be used by links generated in mailer templates.
  config.action_mailer.default_url_options = { host: ENV.fetch("APP_HOST", "silkennet.app"), protocol: "https" }

  # [ARCH.60 / OPS.37 review 2026-09-02] A slot that declares "no mail transport" (the same
  # token `mail_transport_check.rb` honours as its bypass) must not enqueue deliveries that can
  # only die: with SMTP_ADDRESS still a placeholder, every `deliver_later` would fail DNS, retry
  # 25 times and land in a DeadSet nothing scrapes on canopy. One token, one meaning — the flag
  # says the channel is OFF, so deliveries become no-ops (mail still renders, the boot log still
  # carries the bypass warning). Production never sets it: `raise_delivery_errors` stays loud.
  config.action_mailer.perform_deliveries = ENV["SILKENNET_SKIP_MAIL_TRANSPORT_CHECK"] != "1"

  # [ARCH.60] Outgoing SMTP — ENV-driven, no vendor SDK. Every ESP we would pick
  # (Postmark / SES / Mailgun / SendGrid / Resend) speaks plain SMTP, so the vendor
  # stays swappable by changing three variables and nothing else. `delivery_method`
  # is deliberately not restated: production already defaults to `:smtp`.
  #
  # 🔴 The unset case is NOT benign and must not be softened. Assigning this hash
  # replaces Rails' default wholesale, so a missing `SMTP_ADDRESS` yields `nil`
  # rather than the `localhost:25` default — and `mail_transport_check.rb` refuses
  # to boot on it. Before that guard, an unconfigured deploy enqueued the mail,
  # returned 200 to the user, then ground through 25 Sidekiq retries into the dead
  # set: password reset was dead end-to-end with no signal anywhere.
  # ENV names are mirrored in docs/06_04 §2.1; the sender lives in MAIL_FROM
  # (read by `Notifications::DeliveryChannels.configured_sender`).
  config.action_mailer.smtp_settings = {
    address: ENV["SMTP_ADDRESS"].presence,
    port: ENV.fetch("SMTP_PORT", 587).to_i,
    user_name: ENV["SMTP_USER_NAME"].presence,
    password: ENV["SMTP_PASSWORD"].presence,
    # HELO domain — some providers reject the container hostname Net::SMTP would
    # otherwise announce; nil is fine for those that don't care.
    domain: ENV["SMTP_DOMAIN"].presence,
    authentication: ENV.fetch("SMTP_AUTHENTICATION", "plain").to_sym,
    enable_starttls_auto: true
  }

  # NB: `config.i18n.fallbacks` тут НЕ дублюємо — дім один, `application.rb`
  # (Rails-скаффолд ставив сюди `= true`, і воно тихо перекривало інший тамтешній
  # ланцюг; розбіжність dev/test↔prod знято 2026-07-26, `04_04 §12.2`).

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # [SEC.22] ActiveRecord Encryption keys come from ENV, NEVER credentials.yml.enc.
  # Storing them in the vault would deepen the runtime RAILS_MASTER_KEY dependency
  # SEC.22 is dissolving (anyone with host access reads /proc/<pid>/environ). dev/test pin
  # fixtures in their own env files; production reads real >=32-byte values injected
  # per process (web + Sidekiq workers decrypt hardware_keys + identities; the coap
  # daemon only enqueues). ENV[...] not fetch: a nil is caught loudly at boot by
  # config/initializers/active_record_encryption_keys_check.rb instead of raising at
  # the first encrypt/decrypt mid-request. support_unencrypted_data stays false
  # (Rails 8.1 default): hard cutover, no pre-mainnet prod rows, never accept plaintext.
  config.active_record.encryption.primary_key         = ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"]
  config.active_record.encryption.deterministic_key   = ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"]
  config.active_record.encryption.key_derivation_salt = ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"]

  # [PROD] DNS rebinding & Host header attack protection.
  # RAILS_ALLOWED_HOSTS is a comma-separated allowlist (supports leading "."
  # for subdomain wildcards: ".silkennet.com" covers "api.silkennet.com").
  # NOTE: a wildcard does NOT cover a different TLD — the web host must be
  # listed explicitly (canon pair + current value live in 06_04 §2.1).
  # Health check and Prometheus scrape paths are excluded so internal
  # IP-based probes keep working.
  #
  # If RAILS_ALLOWED_HOSTS is empty we log a loud warning at boot but keep
  # the app reachable so a forgotten env var does not blackhole production
  # traffic. Set ALLOW_ALL_HOSTS=true to silence the warning.
  allowed_hosts = ENV.fetch("RAILS_ALLOWED_HOSTS", "").split(",").map(&:strip).reject(&:empty?)
  if allowed_hosts.any?
    config.hosts = allowed_hosts
  elsif ENV["ALLOW_ALL_HOSTS"] != "true"
    config.after_initialize do
      Rails.logger.warn(
        "[SECURITY] RAILS_ALLOWED_HOSTS is unset — DNS rebinding protection is DISABLED. " \
        "Set RAILS_ALLOWED_HOSTS=example.com,.example.com to enable, or ALLOW_ALL_HOSTS=true to silence this warning."
      )
    end
  end
  config.host_authorization = {
    exclude: probe_request
  }
end
