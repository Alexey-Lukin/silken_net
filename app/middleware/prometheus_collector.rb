# frozen_string_literal: true

require "prometheus/client/formats/text"
require "sidekiq/api"

# = ===================================================================
# 📊 PROMETHEUS COLLECTOR MIDDLEWARE
# = ===================================================================
# Rack middleware that serves the /metrics endpoint for Prometheus scraping.
#
# Security (Task 3):
#   1. IP Allowlist — only localhost, private networks (RFC 1918/4193),
#      and IPs from PROMETHEUS_ALLOWED_IPS env var are permitted.
#   2. HTTP Basic Auth — when PROMETHEUS_AUTH_USER and PROMETHEUS_AUTH_PASSWORD
#      are set, requests must provide valid credentials.
#   3. Non-matching IPs or failed auth → 403 Forbidden.
#
# Sidekiq queue gauges are refreshed on each scrape (cheap Sidekiq::Queue API).
class PrometheusCollector
  METRICS_PATH = "/metrics"

  # RFC 1918 + RFC 4193 private ranges (same as Rack::Attack safelist)
  PRIVATE_RANGES = [
    IPAddr.new("127.0.0.0/8"),
    IPAddr.new("::1/128"),
    IPAddr.new("10.0.0.0/8"),
    IPAddr.new("172.16.0.0/12"),
    IPAddr.new("192.168.0.0/16"),
    IPAddr.new("fc00::/7")
  ].freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    request = Rack::Request.new(env)

    unless request.path == METRICS_PATH
      return @app.call(env)
    end

    # --- SECURITY GATE ---
    return forbidden_response unless allowed_ip?(request.ip)
    return forbidden_response unless authorized?(env)

    # --- REFRESH SIDEKIQ GAUGES ---
    refresh_sidekiq_gauges

    # --- RENDER METRICS ---
    body = Prometheus::Client::Formats::Text.marshal(SilkenNet::Metrics::REGISTRY)

    [
      200,
      { "content-type" => Prometheus::Client::Formats::Text::CONTENT_TYPE },
      [body]
    ]
  end

  private

  # Check if the request IP is in the allowlist
  def allowed_ip?(ip)
    parsed = IPAddr.new(ip)

    # Always allow private/localhost
    return true if PRIVATE_RANGES.any? { |range| range.include?(parsed) }

    # Check custom allowlist from ENV
    extra_ips = ENV["PROMETHEUS_ALLOWED_IPS"]
    if extra_ips
      extra_ips.split(",").any? do |allowed|
        IPAddr.new(allowed.strip).include?(parsed)
      end
    else
      false
    end
  rescue IPAddr::InvalidAddressError
    false
  end

  # HTTP Basic Auth (optional — only enforced when ENV vars are set)
  def authorized?(env)
    expected_user = ENV["PROMETHEUS_AUTH_USER"]
    expected_pass = ENV["PROMETHEUS_AUTH_PASSWORD"]

    # If no credentials configured, skip auth (rely on IP allowlist alone)
    return true unless expected_user && expected_pass

    auth = Rack::Auth::Basic::Request.new(env)
    return false unless auth.provided? && auth.basic?

    credentials = auth.credentials
    ActiveSupport::SecurityUtils.secure_compare(credentials[0], expected_user) &&
      ActiveSupport::SecurityUtils.secure_compare(credentials[1], expected_pass)
  end

  # Refresh Sidekiq queue gauges on each Prometheus scrape.
  # Uses Sidekiq::Queue API (reads from Redis, ~1ms per queue).
  def refresh_sidekiq_gauges
    web3_queues = %w[web3 web3_critical]

    web3_queues.each do |queue_name|
      queue = Sidekiq::Queue.new(queue_name)
      SilkenNet::Metrics::WEB3_QUEUE_SIZE.set(queue.size, labels: { queue: queue_name })
      SilkenNet::Metrics::WEB3_QUEUE_LATENCY.set(queue.latency, labels: { queue: queue_name })
    end
  rescue => e
    # Don't let Sidekiq/Redis errors break the metrics endpoint
    Rails.logger.warn "[Prometheus] Failed to refresh Sidekiq gauges: #{e.message}"
  end

  def forbidden_response
    [403, { "content-type" => "text/plain" }, ["Forbidden"]]
  end
end
