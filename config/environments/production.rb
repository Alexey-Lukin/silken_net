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
  config.active_storage.service = :production_mirror

  # VIPS is 10-20x faster than MiniMagick for variant generation (critical at scale).
  # Requires libvips system library (already in Dockerfile base image).
  config.active_storage.variant_processor = :vips

  # Queue variant generation as background jobs — never block the request cycle.
  config.active_storage.resolve_model_to_route = :rails_storage_proxy

  # [PROD] Assume all access to the app is happening through an SSL-terminating reverse proxy
  # (Kamal/Traefik, GCP Load Balancer, Akash Provider). This makes Rails treat upstream HTTP
  # requests as HTTPS and emit secure cookies/links accordingly. Override with DISABLE_SSL=true
  # only for non-TLS canary deployments.
  config.assume_ssl = ENV["DISABLE_SSL"] != "true"

  # [PROD] Force all access to the app over SSL, enable HSTS (1 year + subdomains + preload),
  # and use secure cookies. Health checks (/up, /ready) and Prometheus scrape (/metrics) are excluded so
  # internal probes that hit HTTP directly continue to work.
  config.force_ssl = ENV["DISABLE_SSL"] != "true"
  config.ssl_options = {
    redirect: { exclude: ->(request) { request.path == "/up" || request.path == "/ready" || request.path == "/metrics" } },
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
    json_logger.formatter = proc do |severity, timestamp, progname, msg|
      payload = {
        severity: severity,
        timestamp: timestamp.utc.iso8601(3),
        message: msg.is_a?(String) ? msg : msg.inspect,
        service: "silken_net",
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

  # Ignore bad email addresses and do not raise email delivery errors.
  # Set this to true and configure the email server for immediate delivery to raise delivery errors.
  # config.action_mailer.raise_delivery_errors = false

  # Set host to be used by links generated in mailer templates.
  config.action_mailer.default_url_options = { host: "example.com" }

  # Specify outgoing SMTP server. Remember to add smtp/* credentials via bin/rails credentials:edit.
  # config.action_mailer.smtp_settings = {
  #   user_name: Rails.application.credentials.dig(:smtp, :user_name),
  #   password: Rails.application.credentials.dig(:smtp, :password),
  #   address: "smtp.example.com",
  #   port: 587,
  #   authentication: :plain
  # }

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # [PROD] DNS rebinding & Host header attack protection.
  # RAILS_ALLOWED_HOSTS is a comma-separated allowlist (supports leading "."
  # for subdomain wildcards: e.g. ".silken.net,silken.app"). Health check
  # and Prometheus scrape paths are excluded so internal IP-based probes
  # keep working.
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
    exclude: ->(request) { request.path == "/up" || request.path == "/ready" || request.path == "/metrics" }
  }
end
