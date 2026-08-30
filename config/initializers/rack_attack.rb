# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# = Rack::Attack — Enterprise DDoS / Brute-Force / Bot-Scanner Shield
#
# Protects the SilkenNet platform against:
#   • Volumetric DDoS (global per-IP throttle)
#   • Telemetry endpoint spam (burst-tolerant per-gateway throttle)
#   • Credential stuffing / vulnerability scanning (Fail2Ban on 401/404)
#
# Cache store: RedisCacheStore in dev+prod, MemoryStore in test.
# Redis is REQUIRED, not incidental. Puma runs clustered (WEB_CONCURRENCY=2-4
# forked workers, even at replica count:1), so both the per-IP throttle counters
# AND the fail2ban 401/404 `increment` must be shared + ATOMIC across processes.
# An in-process MemoryStore would fragment both — throttle limits inflate ×N and
# the fail2ban threshold is never reached (scanners never banned); SolidCache's
# increment is not atomic either. Redis is the only correct store here.
#
# 🔴 ONE LOGICAL DATABASE, separated by a key namespace [INF.22]. This block used
# to rewrite the URL path to `/2`, on the assumption that numbered Redis
# databases keep the rate-limit counters away from Sidekiq (/0) and Kredis (/1).
# Upstash exposes exactly one: `SELECT 2` answers `ERR Only 0th database is
# supported!` (measured against our own instance 2026-08-30). The isolation was
# never going to exist in production; the namespace below is what replaces it.
#
# 🔴 AND THE FAILURE MODE IS WHY THIS MATTERS MORE THAN THE ADDRESS. Measured the
# same day: with the `/2` URL, `write`/`read`/`increment` all returned **nil with
# no exception** — `RedisCacheStore`'s failsafe swallows every `Redis::BaseError`.
# That is correct for a cache and wrong for a security counter: a nil read is
# indistinguishable from "this IP has no strikes", so a broken store does not
# degrade the shield, it silently REMOVES it — throttles never count, scanners
# are never banned, and the log stays empty. Hence `error_handler:` below: this
# store is not allowed to fail quietly. ⛔ Do not drop it to keep the block tidy.
#
# 🔴 DECLARED CEILING — REVOKED 2026-08-30, and the reason is worth keeping, because
# the ceiling was not stale, it was WRONG FROM BIRTH. It read: "Upstash is NOT
# same-region, so every throttle check pays a cross-region RTT… a same-region Redis
# sidecar is the real fix and is real infrastructure — gated on first public traffic."
# That verdict was written about a database that did not exist yet. Upstash offers GCP
# `europe-west1` (Belgium) — the same region as our Cloud SQL — so same-region cost one
# choice in a dropdown, not a sidecar and not infrastructure. Both databases now live
# there. ⚠️ This binds terraform: Cloud SQL must STAY in `europe-west1`
# (`terraform/variables.tf` default), or the property is lost without anything reddening.
#
# What survives from that block, because it was measured and is still true: an
# in-process store (MemoryStore / SolidCache) is not a cheaper version of this —
# it is INCORRECT for the reason above, and refusing it traded nothing.

# ---------------------------------------------------------------------------
# 1. CACHE STORE — distributed counters across all application nodes
# ---------------------------------------------------------------------------

# Named on purpose rather than inlined below: the production branch of this file
# never executes under RSpec (test uses MemoryStore), so an inline lambda would be
# unreachable by any behavioural pin — and "no pin" is exactly how the silent
# failure it exists to announce survived in the first place. Extracting it lets
# `spec/initializers/rack_attack_store_spec.rb` CALL it.
RACK_ATTACK_STORE_ERROR_HANDLER = lambda { |method:, returning:, exception:|
  SilkenNet::Metrics::RATE_LIMIT_STORE_ERRORS_TOTAL.increment
  Rails.logger.error(
    "[rack_attack] cache store #{method} failed — RATE LIMITING IS NOT ENFORCED " \
    "while this persists (returned #{returning.inspect}): " \
    "#{exception.class}: #{exception.message}"
  )
}

if Rails.env.test?
  # Use in-memory store for tests — no Redis dependency required.
  Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
else
  Rack::Attack.cache.store = ActiveSupport::Cache::RedisCacheStore.new(
    # `RACK_ATTACK_REDIS_URL` stays the deploy-time lever for pointing the
    # counters at a SEPARATE Redis instance (real isolation, no code change);
    # unset, they share the one database with Sidekiq and Kredis, kept apart by
    # the namespace below.
    url: ENV.fetch("RACK_ATTACK_REDIS_URL") { ENV.fetch("REDIS_URL", "redis://localhost:6379/0") },
    namespace: "rack-attack",
    expires_in: 10.minutes,
    # Give the silence a voice. Without this the store's failsafe returns nil and
    # nothing anywhere records that the shield stopped counting.
    error_handler: RACK_ATTACK_STORE_ERROR_HANDLER
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
  request.ip unless request.path.start_with?("/assets", "/up", "/ready")
end

# ---------------------------------------------------------------------------
# 4. TELEMETRY INGESTION THROTTLE — protect high-value IoT endpoints
#
# Scanned endpoints (from config/routes.rb & controllers):
#   GET  /trees/:id/telemetry           → TelemetryController#tree_history
#   GET  /gateways/:id/telemetry        → TelemetryController#gateway_history
#   GET  /telemetry/live                → TelemetryController#live
#   POST /provisioning/register         → ProvisioningController#register
#   POST /api/v1/gateways/:id/telemetry → TelemetryController#gateway_uplink
#
# ⚠️ [ARCH.77] Це ЄДИНЕ правило, крізь яке поділ дерева проходить усередині —
# але лише на ОДНОМУ зі своїх шляхів: `gateways/:id/telemetry` живе в обох
# контурах (GET-читання на корені, POST-uplink під `/api/v1`), решта три —
# одноконтурні. Саме через ту одну пару потрібна опційна префікс-група, а не
# два правила: дискримінатор спільний (UID/IP), тож окреме правило дало б тій
# самій поверхні другі 60 запитів на хвилину — тихе подвоєння стелі. Для трьох
# інших шляхів жодного подвоєння не існує; група накриває їхні `/api/v1`-форми
# як мертві дзеркала (404 → лише fail2ban-шум від сканерів).
#
# Allows bursts (60 req/min) but blocks sustained spamming.
# Discriminator: Gateway UID (from "X-Gateway-UID" header) or IP.
# ---------------------------------------------------------------------------
TELEMETRY_PATH_PATTERN = %r{\A(?:/api/v1)?/(trees/\d+/telemetry|gateways/\d+/telemetry|telemetry/live|provisioning/register)}

Rack::Attack.throttle("telemetry/uid", limit: 60, period: 1.minute) do |request|
  if request.path.match?(TELEMETRY_PATH_PATTERN)
    request.env["HTTP_X_GATEWAY_UID"].presence || request.ip
  end
end

# ---------------------------------------------------------------------------
# 5. LOGIN / AUTH THROTTLE — protect sessions & passwords endpoints
# ---------------------------------------------------------------------------
# [SEC.29] Дієслова — обидва, і це не «про всяк випадок»: `reset_password`
# зареєстровано як **PATCH** (`routes.rb`), тож умова `post?` мовчки виводила
# з-під ліміту єдиний крок ланцюга, що реально МІНЯЄ пароль. Сусідній
# `account_security`-throttle цю вісь уже знав (`%w[PATCH DELETE]`) — розходження
# сиділо в межах одного файла. Over-inclusive тут безпечне: зайве дієслово на
# живому шляху лише рахує запит, якого роутер однаково не прийме.
Rack::Attack.throttle("logins/ip", limit: 10, period: 1.minute) do |request|
  if request.path.match?(%r{\A/(login|forgot_password|reset_password)\z}) &&
     (request.post? || request.patch?)
    request.ip
  end
end

# ---------------------------------------------------------------------------
# 5c. ACCOUNT SECURITY THROTTLE [SEC.16] — step-up brute-force guard:
# підбір current_password на password-change / MFA-toggle / erase. Keyed на IP
# (Rack::Attack сидить перед session-middleware — user_id тут недоступний;
# IP = actor-проксі, дзеркало logins/ip вище).
# ---------------------------------------------------------------------------
Rack::Attack.throttle("account_security/ip", limit: 10, period: 1.minute) do |request|
  if request.path.start_with?("/account_security") &&
     %w[PATCH DELETE].include?(request.request_method)
    request.ip
  end
end

# ---------------------------------------------------------------------------
# 5a. M2M AUTH THROTTLE — prevent DID enumeration & Ed25519 DoS
# ---------------------------------------------------------------------------
# [SEC.29] Префікс, а не `==`: `/auth/m2m_token/refresh` — окремий POST-маршрут
# ТІЄЇ САМОЇ Ed25519/DID-поверхні, тобто рівно те, від чого правило й ставили
# («DID enumeration & Ed25519 DoS»), — а точне порівняння його не бачило. Клас
# сусідній до дієслівного: там правило дивилось не на те дієслово, тут — не на
# весь шлях, який саме́ ж і декларує захищати.
Rack::Attack.throttle("m2m_auth/ip", limit: 15, period: 1.minute) do |request|
  if request.path.start_with?("/api/v1/auth/m2m_token") && request.post?
    request.ip
  end
end

# ---------------------------------------------------------------------------
# 5b. ORACLE CALLBACKS THROTTLE — limit Chainlink DON callback rate
# ---------------------------------------------------------------------------
Rack::Attack.throttle("oracle_callbacks/ip", limit: 60, period: 1.minute) do |request|
  if request.path == "/api/v1/oracle_callbacks" && request.post?
    request.ip
  end
end

# ---------------------------------------------------------------------------
# 5b'. HELIUM SOS THROTTLE — [ARCH.34 L3] webhook Helium Console.
# Легітимний трафік = поодинокі SOS-ретрансміти аварійної Королеви (частки
# кадру/хв на шлюз); 30/хв на IP душить flood ще до HMAC-перевірки.
# ---------------------------------------------------------------------------
Rack::Attack.throttle("helium_sos/ip", limit: 30, period: 1.minute) do |request|
  if request.path == "/api/v1/telemetry/helium" && request.post?
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

        # Atomic increment — avoids race conditions under concurrent requests.
        store.increment(count_key, 1, expires_in: FAIL2BAN_FINDTIME)
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
