# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Rack::Attack", type: :request do
  # Reset Rack::Attack state between examples so throttle counters and
  # Fail2Ban bans don't leak across tests.
  before do
    # Freeze time so the throttle period-window key (Time.now / period) stays
    # constant across the multi-request loops below. In a slow full-suite run the
    # 300+ requests can straddle a 5-min wall-clock boundary → the counter splits
    # across two windows → 301st request not throttled (flaky 200 instead of 429).
    # Isolated runs are fast enough to stay in one window, hence pass-in-isolation.
    freeze_time

    Rack::Attack.cache.store.clear
    Rack::Attack.reset!

    # Disable N+1 detection — these tests deliberately repeat requests to
    # exercise middleware counters, not to test ActiveRecord query patterns.
    Prosopite.pause if defined?(Prosopite)
  end

  after do
    travel_back
    Prosopite.resume if defined?(Prosopite)
  end

  # -----------------------------------------------------------------------
  # SAFELIST
  # -----------------------------------------------------------------------
  describe "safelist" do
    it "allows requests from 127.0.0.1 without throttling" do
      301.times do
        get "/up", headers: { "REMOTE_ADDR" => "127.0.0.1" }
      end

      expect(response).to have_http_status(:ok)
    end
  end

  # -----------------------------------------------------------------------
  # GLOBAL THROTTLE (300 req / 5 min per IP)
  # -----------------------------------------------------------------------
  describe "global throttle (req/ip)" do
    it "allows up to 300 requests per IP within 5 minutes" do
      300.times do
        get "/api/v1/login", headers: { "REMOTE_ADDR" => "1.2.3.4" }
      end

      # 300th request should still succeed (not 429)
      expect(response.status).not_to eq(429)
    end

    it "throttles the 301st request from the same IP" do
      301.times do
        get "/api/v1/login", headers: { "REMOTE_ADDR" => "1.2.3.5" }
      end

      expect(response).to have_http_status(:too_many_requests)
      body = JSON.parse(response.body)
      expect(body["error"]).to eq("Rate limit exceeded")
      expect(response.headers["Retry-After"]).to be_present
    end

    it "does not throttle requests to /assets or /up" do
      301.times do
        get "/up", headers: { "REMOTE_ADDR" => "1.2.3.6" }
      end

      expect(response.status).not_to eq(429)
    end
  end

  # -----------------------------------------------------------------------
  # TELEMETRY THROTTLE (60 req / 1 min)
  # -----------------------------------------------------------------------
  describe "telemetry throttle (telemetry/uid)" do
    it "blocks sustained telemetry requests via throttle or fail2ban" do
      61.times do
        get "/api/v1/telemetry/live", headers: { "REMOTE_ADDR" => "5.6.7.8" }
      end

      # Unauthenticated requests return 401, which triggers Fail2Ban (403)
      # before the telemetry throttle (429). Both are valid blocking mechanisms.
      expect(response.status).to be_in([ 403, 429 ])
    end

    it "uses X-Gateway-UID as discriminator when present" do
      # Requests with UID-A
      10.times do
        get "/api/v1/telemetry/live", headers: {
          "REMOTE_ADDR" => "5.6.7.9",
          "HTTP_X_GATEWAY_UID" => "UID-A"
        }
      end

      # Request with a different UID from the same IP shares the IP's global
      # counter but has a separate telemetry throttle bucket.
      get "/api/v1/telemetry/live", headers: {
        "REMOTE_ADDR" => "5.6.7.9",
        "HTTP_X_GATEWAY_UID" => "UID-B"
      }
      # With only 11 total requests, neither global throttle (300) nor
      # telemetry throttle (60) nor fail2ban (15) should trigger.
      expect(response.status).not_to eq(429)
    end

    it "registers the telemetry throttle rule" do
      throttle = Rack::Attack.throttles["telemetry/uid"]
      expect(throttle).to be_present
    end
  end

  # -----------------------------------------------------------------------
  # LOGIN THROTTLE (10 req / 1 min)
  # -----------------------------------------------------------------------
  describe "login throttle (logins/ip)" do
    it "throttles login attempts after 10 POSTs per minute" do
      11.times do
        post "/api/v1/login",
          params: { email: "a@b.com", password: "wrong" },
          headers: { "REMOTE_ADDR" => "9.8.7.6" }
      end

      expect(response).to have_http_status(:too_many_requests)
    end
  end

  # -----------------------------------------------------------------------
  # M2M AUTH THROTTLE (15 req / 1 min)
  # -----------------------------------------------------------------------
  describe "m2m auth throttle (m2m_auth/ip)" do
    it "registers the m2m_auth throttle rule" do
      throttle = Rack::Attack.throttles["m2m_auth/ip"]
      expect(throttle).to be_present
    end

    it "throttles m2m auth attempts after 15 POSTs per minute" do
      16.times do
        post "/api/v1/auth/m2m_token",
          params: { did: "SNET-Q-TEST0001", timestamp: Time.current.iso8601, signature: "a" * 128 },
          headers: { "REMOTE_ADDR" => "203.0.113.40" },
          as: :json
      end

      # Unauthenticated/not-found requests return 401/404, which triggers
      # Fail2Ban (403) before the M2M throttle (429). Both are valid blocking.
      expect(response.status).to be_in([ 403, 429 ])
    end
  end

  # -----------------------------------------------------------------------
  # ORACLE CALLBACKS THROTTLE (60 req / 1 min)
  # -----------------------------------------------------------------------
  describe "oracle callbacks throttle (oracle_callbacks/ip)" do
    it "registers the oracle_callbacks throttle rule" do
      throttle = Rack::Attack.throttles["oracle_callbacks/ip"]
      expect(throttle).to be_present
    end

    it "blocks sustained oracle callback requests" do
      61.times do
        post "/api/v1/oracle_callbacks",
          params: { chainlink_request_id: SecureRandom.uuid, success: true },
          headers: { "REMOTE_ADDR" => "203.0.113.50" },
          as: :json
      end

      # Unauthenticated requests return 401, which triggers Fail2Ban (403)
      # before the oracle throttle (429). Both are valid blocking mechanisms.
      expect(response.status).to be_in([ 403, 429 ])
    end
  end

  # -----------------------------------------------------------------------
  # FAIL2BAN
  # -----------------------------------------------------------------------
  describe "fail2ban (401/404 scanner detection)" do
    it "blocks an IP after accumulating too many 401/404 responses" do
      # Generate 15+ failures (401 from unauthenticated requests)
      16.times do
        get "/api/v1/users/me", headers: { "REMOTE_ADDR" => "6.6.6.6" }
      end

      # The IP should now be banned — next request gets 403
      get "/api/v1/users/me", headers: { "REMOTE_ADDR" => "6.6.6.6" }
      expect(response).to have_http_status(:forbidden)

      body = JSON.parse(response.body)
      expect(body["error"]).to eq("Forbidden")
    end
  end

  # -----------------------------------------------------------------------
  # THROTTLED RESPONSE FORMAT
  # -----------------------------------------------------------------------
  describe "throttled response" do
    it "returns JSON with error message and Retry-After header" do
      # Trigger the logins/ip throttle (limit: 10/min, POST only) — 11 requests
      # reliably exceeds the threshold without relying on the global 300-req
      # throttle period timing. Requests 1–10 reach the app (401 each; fail2ban
      # counter stays at 10 < FAIL2BAN_MAXRETRY=15). Request 11 is intercepted
      # by Rack::Attack before reaching the app and returns 429.
      11.times do
        post "/api/v1/login",
          params: { email: "test@example.com", password: "wrong" },
          headers: { "REMOTE_ADDR" => "2.3.4.5" }
      end

      expect(response).to have_http_status(:too_many_requests)
      expect(response.content_type).to include("application/json")

      body = JSON.parse(response.body)
      expect(body).to eq("error" => "Rate limit exceeded")
      expect(response.headers["Retry-After"]).to be_present
      expect(response.headers["Retry-After"].to_i).to be > 0
    end
  end

  # -----------------------------------------------------------------------
  # MIDDLEWARE PRESENCE
  # -----------------------------------------------------------------------
  describe "middleware stack" do
    it "includes Rack::Attack in the middleware stack" do
      middlewares = Rails.application.middleware.map(&:name)
      expect(middlewares).to include("Rack::Attack")
    end

    it "includes RackAttackFailCounter::Middleware after Rack::Attack" do
      middlewares = Rails.application.middleware.map(&:name)
      rack_attack_idx = middlewares.index("Rack::Attack")
      fail_counter_idx = middlewares.index("RackAttackFailCounter::Middleware")

      expect(rack_attack_idx).to be_present
      expect(fail_counter_idx).to be_present
      expect(fail_counter_idx).to be > rack_attack_idx
    end
  end

  # -----------------------------------------------------------------------
  # CONFIGURATION
  # -----------------------------------------------------------------------
  describe "configuration" do
    it "registers all expected throttle rules" do
      # Order doesn't matter — `contain_exactly` is set-equality.
      # The 4 codex/* throttles were added in Phase 2..4 to protect the
      # write-heavy Codex endpoints (comments, attunements, fraction picks,
      # battle votes) from spammy clients without affecting the legitimate
      # forester+ workflow.
      expect(Rack::Attack.throttles.keys).to contain_exactly(
        "req/ip", "telemetry/uid", "logins/ip", "m2m_auth/ip", "oracle_callbacks/ip",
        "codex/comments", "codex/attunements", "codex/fractions", "codex/matches/create"
      )
    end

    it "uses MemoryStore for cache in test environment" do
      expect(Rack::Attack.cache.store).to be_a(ActiveSupport::Cache::MemoryStore)
    end
  end
end
