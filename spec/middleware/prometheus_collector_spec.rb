# frozen_string_literal: true

require "rails_helper"

RSpec.describe PrometheusCollector, type: :request do
  before do
    # Disable N+1 detection — these tests exercise middleware, not ActiveRecord.
    Prosopite.pause if defined?(Prosopite)
  end

  after do
    Prosopite.resume if defined?(Prosopite)
  end

  # -----------------------------------------------------------------------
  # PASSTHROUGH (non-/metrics requests)
  # -----------------------------------------------------------------------
  describe "passthrough" do
    it "passes non-/metrics requests to the app" do
      get "/up"
      expect(response).to have_http_status(:ok)
    end
  end

  # -----------------------------------------------------------------------
  # /metrics ENDPOINT — ACCESS CONTROL
  # -----------------------------------------------------------------------
  describe "GET /metrics" do
    context "when accessed from localhost (127.0.0.1)" do
      it "returns Prometheus text output" do
        get "/metrics", headers: { "REMOTE_ADDR" => "127.0.0.1" }

        expect(response).to have_http_status(:ok)
        expect(response.content_type).to include("text/plain")
        expect(response.body).to include("silkennet_scc_minted_total")
        expect(response.body).to include("silkennet_telemetry_processed_total")
      end
    end

    context "when accessed from private network (10.x.x.x)" do
      it "returns metrics" do
        get "/metrics", headers: { "REMOTE_ADDR" => "10.0.1.50" }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("silkennet_rpc_errors_total")
      end
    end

    context "when accessed from private network (172.16.x.x)" do
      it "returns metrics" do
        get "/metrics", headers: { "REMOTE_ADDR" => "172.16.0.1" }
        expect(response).to have_http_status(:ok)
      end
    end

    context "when accessed from private network (192.168.x.x)" do
      it "returns metrics" do
        get "/metrics", headers: { "REMOTE_ADDR" => "192.168.1.1" }
        expect(response).to have_http_status(:ok)
      end
    end

    context "when accessed from public IP (not in allowlist)" do
      it "returns 403 Forbidden" do
        get "/metrics", headers: { "REMOTE_ADDR" => "8.8.8.8" }

        expect(response).to have_http_status(:forbidden)
        expect(response.body).to eq("Forbidden")
      end
    end

    context "when accessed from IP in PROMETHEUS_ALLOWED_IPS env" do
      around do |example|
        original = ENV["PROMETHEUS_ALLOWED_IPS"]
        ENV["PROMETHEUS_ALLOWED_IPS"] = "203.0.113.0/24,198.51.100.5"
        example.run
      ensure
        if original
          ENV["PROMETHEUS_ALLOWED_IPS"] = original
        else
          ENV.delete("PROMETHEUS_ALLOWED_IPS")
        end
      end

      it "allows IPs from the custom allowlist" do
        get "/metrics", headers: { "REMOTE_ADDR" => "203.0.113.42" }
        expect(response).to have_http_status(:ok)
      end

      it "allows exact IPs from the custom allowlist" do
        get "/metrics", headers: { "REMOTE_ADDR" => "198.51.100.5" }
        expect(response).to have_http_status(:ok)
      end

      it "rejects IPs not in the custom allowlist" do
        get "/metrics", headers: { "REMOTE_ADDR" => "198.51.100.6" }
        expect(response).to have_http_status(:forbidden)
      end
    end

    # -----------------------------------------------------------------------
    # HTTP BASIC AUTH
    # -----------------------------------------------------------------------
    context "with HTTP Basic Auth configured" do
      around do |example|
        original_user = ENV["PROMETHEUS_AUTH_USER"]
        original_pass = ENV["PROMETHEUS_AUTH_PASSWORD"]
        ENV["PROMETHEUS_AUTH_USER"] = "prom"
        ENV["PROMETHEUS_AUTH_PASSWORD"] = "secret123"
        example.run
      ensure
        if original_user
          ENV["PROMETHEUS_AUTH_USER"] = original_user
        else
          ENV.delete("PROMETHEUS_AUTH_USER")
        end
        if original_pass
          ENV["PROMETHEUS_AUTH_PASSWORD"] = original_pass
        else
          ENV.delete("PROMETHEUS_AUTH_PASSWORD")
        end
      end

      it "returns 403 when no credentials are provided from localhost" do
        get "/metrics", headers: { "REMOTE_ADDR" => "127.0.0.1" }
        expect(response).to have_http_status(:forbidden)
      end

      it "returns 403 with wrong credentials" do
        get "/metrics", headers: {
          "REMOTE_ADDR" => "127.0.0.1",
          "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials("prom", "wrong")
        }
        expect(response).to have_http_status(:forbidden)
      end

      it "returns metrics with correct credentials" do
        get "/metrics", headers: {
          "REMOTE_ADDR" => "127.0.0.1",
          "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials("prom", "secret123")
        }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("silkennet_")
      end
    end

    # -----------------------------------------------------------------------
    # SIDEKIQ GAUGE REFRESH
    # -----------------------------------------------------------------------
    describe "Sidekiq gauge refresh" do
      it "includes web3 queue size gauges in output" do
        get "/metrics", headers: { "REMOTE_ADDR" => "127.0.0.1" }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("silkennet_web3_queue_size")
        expect(response.body).to include("silkennet_web3_queue_latency_seconds")
      end
    end
  end

  # -----------------------------------------------------------------------
  # MIDDLEWARE STACK
  # -----------------------------------------------------------------------
  describe "middleware stack" do
    it "includes PrometheusCollector in the middleware stack" do
      middlewares = Rails.application.middleware.map(&:name)
      expect(middlewares).to include("PrometheusCollector")
    end
  end
end
