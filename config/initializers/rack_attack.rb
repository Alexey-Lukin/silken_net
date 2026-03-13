# frozen_string_literal: true

# = Rack::Attack — Enterprise DDoS / Brute-Force / Bot-Scanner Shield
#
# Protects the Gaia 2.0 platform against:
#   • Volumetric DDoS (global per-IP throttle)
#   • Telemetry endpoint spam (burst-tolerant per-gateway throttle)
#   • Credential stuffing / vulnerability scanning (Fail2Ban on 401/404)
#
# Cache store: Rails.cache (Solid Cache in production, memory in dev/test)
# so rate-limit counters are shared across all Akash/Kamal cloud nodes.

# ---------------------------------------------------------------------------
# 1. CACHE STORE — distributed counters across all application nodes
# ---------------------------------------------------------------------------
if Rails.env.test?
  # Use in-memory store for tests — no Redis dependency required.
  Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
else
  Rack::Attack.cache.store = ActiveSupport::Cache::RedisCacheStore.new(
    url: ENV.fetch("RACK_ATTACK_REDIS_URL") {
      # Isolate rate-limit counters on DB 2 to avoid interference with
      # Sidekiq (DB 0) and Kredis locks (DB 1).
      base = ENV.fetch("REDIS_URL", "redis://localhost:6379/0")
      base.sub(%r{/\d+\z}, "/2")
    },
    expires_in: 10.minutes
  )
end

# ---------------------------------------------------------------------------
# 2. SAFELIST — never throttle/ban trusted traffic
# ---------------------------------------------------------------------------
Rack::Attack.safelist("allow-localhost") do |request|
  ip = request.ip
  ip == "127.0.0.1" || ip == "::1"
end

Rack::Attack.safelist("allow-private-networks") do |request|
  ip = IPAddr.new(request.ip)

  # RFC 1918 + RFC 4193 private ranges
  [
    IPAddr.new("10.0.0.0/8"),
    IPAddr.new("172.16.0.0/12"),
    IPAddr.new("192.168.0.0/16"),
    IPAddr.new("fc00::/7")
  ].any? { |range| range.include?(ip) }
rescue IPAddr::InvalidAddressError
  false
end

# ---------------------------------------------------------------------------
# 3. GLOBAL THROTTLE — 300 requests per 5 minutes per IP
# ---------------------------------------------------------------------------
Rack::Attack.throttle("req/ip", limit: 300, period: 5.minutes) do |request|
  request.ip unless request.path.start_with?("/assets", "/up")
end

# ---------------------------------------------------------------------------
# 4. TELEMETRY INGESTION THROTTLE — protect high-value IoT endpoints
#
# Scanned endpoints (from config/routes.rb & controllers):
#   GET /api/v1/trees/:id/telemetry    → TelemetryController#tree_history
#   GET /api/v1/gateways/:id/telemetry → TelemetryController#gateway_history
#   GET /api/v1/telemetry/live          → TelemetryController#live
#   POST /api/v1/provisioning/register  → ProvisioningController#register
#
# Allows bursts (60 req/min) but blocks sustained spamming.
# Discriminator: Gateway UID (from "X-Gateway-UID" header) or IP.
# ---------------------------------------------------------------------------
TELEMETRY_PATH_PATTERN = %r{\A/api/v1/(trees/\d+/telemetry|gateways/\d+/telemetry|telemetry/live|provisioning/register)}

Rack::Attack.throttle("telemetry/uid", limit: 60, period: 1.minute) do |request|
  if request.path.match?(TELEMETRY_PATH_PATTERN)
    request.env["HTTP_X_GATEWAY_UID"].presence || request.ip
  end
end

# ---------------------------------------------------------------------------
# 5. LOGIN / AUTH THROTTLE — protect sessions & passwords endpoints
# ---------------------------------------------------------------------------
Rack::Attack.throttle("logins/ip", limit: 10, period: 1.minute) do |request|
  if request.path.match?(%r{\A/api/v1/(login|forgot_password|reset_password)\z}) && request.post?
    request.ip
  end
end

# ---------------------------------------------------------------------------
# 6. FAIL2BAN — ban IPs that return too many 401/404 errors
#
# Rack::Attack blocklists run *before* the response, so we cannot inspect
# the HTTP status directly. Instead we use a two-phase approach:
#
#   Phase A (after_response): A Rails middleware callback increments a
#           per-IP failure counter in the cache when a 401 or 404 is returned.
#   Phase B (blocklist):      On the *next* request from that IP, the
#           blocklist checks the counter and bans the IP if the threshold
#           is exceeded.
#
# Thresholds: 15 failures within 5 minutes → 30-minute ban.
# ---------------------------------------------------------------------------
FAIL2BAN_CACHE_PREFIX = "rack::attack:fail2ban:"
FAIL2BAN_MAXRETRY     = 15
FAIL2BAN_FINDTIME     = 5.minutes.to_i
FAIL2BAN_BANTIME      = 30.minutes.to_i

Rack::Attack.blocklist("fail2ban/scanners") do |request|
  ip = request.ip
  ban_key   = "#{FAIL2BAN_CACHE_PREFIX}ban:#{ip}"
  count_key = "#{FAIL2BAN_CACHE_PREFIX}count:#{ip}"
  store     = Rack::Attack.cache.store

  # Already banned?
  if store.read(ban_key)
    true
  else
    count = store.read(count_key).to_i
    if count >= FAIL2BAN_MAXRETRY
      # Ban the IP for the configured bantime
      store.write(ban_key, true, expires_in: FAIL2BAN_BANTIME)
      true
    else
      false
    end
  end
end

# Phase A: After each response, track 401/404 failures per IP.
module RackAttackFailCounter
  class Middleware
    def initialize(app)
      @app = app
    end

    def call(env)
      status, headers, body = @app.call(env)

      if [ 401, 404 ].include?(status)
        ip = ActionDispatch::Request.new(env).ip
        count_key = "#{FAIL2BAN_CACHE_PREFIX}count:#{ip}"
        store = Rack::Attack.cache.store

        current = store.read(count_key).to_i
        store.write(count_key, current + 1, expires_in: FAIL2BAN_FINDTIME)
      end

      [ status, headers, body ]
    end
  end
end

Rails.application.config.middleware.insert_after Rack::Attack, RackAttackFailCounter::Middleware

# ---------------------------------------------------------------------------
# 7. THROTTLED RESPONSE — minimal JSON, no wasted CPU on HTML rendering
# ---------------------------------------------------------------------------
Rack::Attack.throttled_responder = lambda do |request|
  match_data = request.env["rack.attack.match_data"] || {}
  retry_after = (match_data[:period] || 300).to_i

  headers = {
    "Content-Type" => "application/json; charset=utf-8",
    "Retry-After" => retry_after.to_s
  }

  body = JSON.generate({ error: "Rate limit exceeded" })

  [ 429, headers, [ body ] ]
end

Rack::Attack.blocklisted_responder = lambda do |request|
  headers = {
    "Content-Type" => "application/json; charset=utf-8",
    "Retry-After" => "1800"
  }

  body = JSON.generate({ error: "Forbidden" })

  [ 403, headers, [ body ] ]
end

# ---------------------------------------------------------------------------
# 8. OBSERVABILITY — log every throttle/block/ban to Rails.logger
# ---------------------------------------------------------------------------
ActiveSupport::Notifications.subscribe("throttle.rack_attack") do |_name, _start, _finish, _id, payload|
  request = payload[:request]
  Rails.logger.warn(
    "[Rack::Attack] Throttled #{request.ip} on #{request.request_method} #{request.path} " \
    "(matched: #{request.env['rack.attack.matched']})"
  )
end

ActiveSupport::Notifications.subscribe("blocklist.rack_attack") do |_name, _start, _finish, _id, payload|
  request = payload[:request]
  Rails.logger.warn(
    "[Rack::Attack] Blocked #{request.ip} on #{request.request_method} #{request.path} " \
    "(matched: #{request.env['rack.attack.matched']})"
  )
end

ActiveSupport::Notifications.subscribe("track.rack_attack") do |_name, _start, _finish, _id, payload|
  request = payload[:request]
  Rails.logger.info(
    "[Rack::Attack] Tracked #{request.ip} on #{request.request_method} #{request.path} " \
    "(matched: #{request.env['rack.attack.matched']})"
  )
end
