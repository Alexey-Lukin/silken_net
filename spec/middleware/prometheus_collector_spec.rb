# SPDX-License-Identifier: AGPL-3.0-or-later
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
    # Назва обіцяє, що запит дійшов ДО ЗАСТОСУНКУ, а не що він завершився 200:
    # флип `unless`→`if` завернув би `/up` у рендер метрик, і той теж віддав би
    # 200 (`REMOTE_ADDR` у rack-test = 127.0.0.1, тобто гард пропускає). Тож пін
    # мусить називати, ЧИЄ це тіло.
    it "passes non-/metrics requests to the app" do
      get "/up"

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("silkennet_")
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
    # Gauge refresh runs ONLY inside the job process (`if Sidekiq.server?`, §2.9 triple-target
    # de-dup). RSpec is not a Sidekiq server → без цього стабу refresh_sidekiq_gauges НЕ бігає,
    # і «Redis error» тест був би вакуумним (raise ніколи не стрілив би).
    describe "Sidekiq gauge refresh (job-process scrape)" do
      before { allow(Sidekiq).to receive(:server?).and_return(true) }

      it "refreshes all nine strict-priority queue gauges on scrape" do
        # Один Sidekiq::Queue.new на кожну з 9 черг (uplink…low) — не-вакуумний доказ, що
        # refresh_sidekiq_gauges справді відпрацював, а не лише зареєстровані імена метрик.
        allow(Sidekiq::Queue).to receive(:new).and_call_original

        get "/metrics", headers: { "REMOTE_ADDR" => "127.0.0.1" }

        expect(Sidekiq::Queue).to have_received(:new).exactly(9).times
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("silkennet_sidekiq_queue_size")
        expect(response.body).to include("silkennet_sidekiq_queue_latency_seconds")
      end

      it "refreshes the DeadSet size gauge [ARCH.45]" do
        allow(Sidekiq::DeadSet).to receive(:new).and_call_original

        get "/metrics", headers: { "REMOTE_ADDR" => "127.0.0.1" }

        expect(Sidekiq::DeadSet).to have_received(:new)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("silkennet_sidekiq_dead_set_size")
      end
    end

    describe "on-scrape gauges without a Sidekiq server (web/coap targets)" do
      it "renders metrics but skips the Sidekiq refresh when not a server process" do
        allow(Sidekiq::Queue).to receive(:new) # §2.9: тільки job-процес семплить черги
        allow(Sidekiq).to receive(:server?).and_return(false)

        get "/metrics", headers: { "REMOTE_ADDR" => "127.0.0.1" }

        expect(Sidekiq::Queue).not_to have_received(:new)
        expect(response).to have_http_status(:ok)
      end
    end

    context "when IP address is invalid" do
      it "returns 403 Forbidden" do
        get "/metrics", headers: { "REMOTE_ADDR" => "not_an_ip" }
        expect(response).to have_http_status(:forbidden)
      end
    end

    context "when a public IP is checked and no custom allowlist is configured" do
      around do |example|
        original = ENV.delete("PROMETHEUS_ALLOWED_IPS") # force the extra_ips=nil else-branch
        example.run
      ensure
        ENV["PROMETHEUS_ALLOWED_IPS"] = original if original
      end

      it "returns 403 Forbidden (allowlist absent → no fallback grant)" do
        get "/metrics", headers: { "REMOTE_ADDR" => "8.8.8.8" }
        expect(response).to have_http_status(:forbidden)
      end
    end

    context "when Sidekiq/Redis is unavailable during gauge refresh" do
      it "still returns metrics despite a Sidekiq error (rescue keeps the endpoint up)" do
        allow(Sidekiq).to receive(:server?).and_return(true) # інакше refresh не бігав би — тест вакуумний
        allow(Sidekiq::Queue).to receive(:new).and_raise(Redis::CannotConnectError)

        get "/metrics", headers: { "REMOTE_ADDR" => "127.0.0.1" }
        expect(response).to have_http_status(:ok)
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
