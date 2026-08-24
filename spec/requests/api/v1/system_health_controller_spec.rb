# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::SystemHealthController, type: :request do
  let(:organization) { create(:organization) }
  let(:admin_user) { create(:user, :admin, organization: organization) }
  let(:regular_user) { create(:user, organization: organization) }
  let(:admin_token) { admin_user.generate_token_for(:api_access) }
  let(:regular_token) { regular_user.generate_token_for(:api_access) }
  let(:admin_headers) { { "Authorization" => "Bearer #{admin_token}" } }
  let(:regular_headers) { { "Authorization" => "Bearer #{regular_token}" } }

  # Демон CoAP живе поза цим процесом, тож адреса приходить із оточення.
  # Незадана вона означає «не знаю» — і саме це відрізнення пінить перший
  # приклад нижче.
  def with_coap_host(host)
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("COAP_HOST").and_return(host)
  end

  describe "GET /system_health" do
    it "returns system health status for admin users" do
      get "/system_health", headers: admin_headers, as: :json
      expect(response).to have_http_status(:ok)

      body = response.parsed_body
      expect(body).to include("checked_at", "coap_listener", "sidekiq", "database")
      expect(body["coap_listener"]).to include("status", "port")
      expect(body["database"]).to include("connected")
    end

    it "returns 403 for non-admin users" do
      get "/system_health", headers: regular_headers, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    # [ARCH.81] Несучий пін пункту. Доти проба відкривала TCP-сокет на UDP-порт
    # loopback'а: `ECONNREFUSED` був гарантований, тож вердикт не залежав від
    # стану світу, а спека цементувала його, стабаючи `TCPSocket` і пінячи
    # `alive: false`. Тепер «не сконфігуровано» — власний стан, і сплутати його
    # з «мертвий» більше не можна.
    context "when the CoAP address is not configured" do
      it "says so instead of reporting the intake dead" do
        with_coap_host(nil)

        get "/system_health", headers: admin_headers, as: :json

        coap = response.parsed_body["coap_listener"]
        expect(coap["status"]).to eq("not_configured")
        expect(coap["status"]).not_to eq("unreachable")
      end
    end

    context "when the CoAP address is configured but nothing answers" do
      it "reports the intake unreachable after a real UDP round-trip" do
        # Порт, на якому ніхто не слухає: ядро віддає ICMP port-unreachable,
        # тож вердикт приходить із мережі, а не з конструкції проби.
        with_coap_host("127.0.0.1")
        allow(ENV).to receive(:fetch).and_call_original
        allow(ENV).to receive(:fetch).with("COAP_PORT", CoapSmoke::DEFAULT_PORT).and_return(1)

        get "/system_health", headers: admin_headers, as: :json

        expect(response.parsed_body["coap_listener"]["status"]).to eq("unreachable")
      end
    end

    it "does not leak the raw exception text when the probe itself blows up" do
      allow(SilkenNet::HealthProbes).to receive(:coap_verdict).and_raise(StandardError, "socket internals")

      with_coap_host("127.0.0.1")
      get "/system_health", headers: admin_headers, as: :json

      coap = response.parsed_body["coap_listener"]
      expect(coap["status"]).to eq("check_failed")
      expect(coap.to_s).not_to include("socket internals")
    end

    # Картка зветься «Sidekiq Workers», тож живість — це наявність ПРОЦЕСІВ.
    # `Sidekiq::Stats` відповідає, поки живий Redis, і доти саме ця відповідь
    # малювалась зеленим над мертвим флотом воркерів.
    it "reports Sidekiq dead when no worker process is registered" do
      allow(SilkenNet::HealthProbes).to receive(:sidekiq_process_count).and_return(0)

      get "/system_health", headers: admin_headers, as: :json

      sidekiq = response.parsed_body["sidekiq"]
      expect(sidekiq["alive"]).to be(false)
      expect(sidekiq["processes"]).to eq(0)
    end

    it "reports Sidekiq alive when a worker process is registered" do
      allow(SilkenNet::HealthProbes).to receive(:sidekiq_process_count).and_return(2)

      get "/system_health", headers: admin_headers, as: :json

      expect(response.parsed_body["sidekiq"]["alive"]).to be(true)
    end

    it "handles Sidekiq stats errors gracefully" do
      allow(Sidekiq::Stats).to receive(:new).and_raise(RuntimeError, "Connection refused")

      get "/system_health", headers: admin_headers, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["sidekiq"]).to have_key("error")
      expect(body["sidekiq"]["alive"]).to be(false)
    end

    # Проба бази робить `SELECT 1` — раунд-тріп, а не запит до обʼєкта
    # зʼєднання про його власну думку про себе (`connection.active?` лишався
    # true й тоді, коли сервер уже помер).
    it "proves the database by round-trip, not by asking the connection object" do
      allow(ActiveRecord::Base.connection).to receive(:execute).with("SELECT 1").and_call_original

      get "/system_health", headers: admin_headers, as: :json

      expect(ActiveRecord::Base.connection).to have_received(:execute).with("SELECT 1")
      expect(response.parsed_body["database"]["connected"]).to be(true)
    end

    it "handles database connection failures gracefully" do
      allow(ActiveRecord::Base.connection).to receive(:execute).and_raise(RuntimeError, "could not connect")

      get "/system_health", headers: admin_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["database"]["connected"]).to be(false)
    end

    it "returns all expected top-level keys in the response" do
      stats = instance_double(Sidekiq::Stats, enqueued: 0, processed: 100, failed: 2, workers_size: 4, queues: {})
      allow(Sidekiq::Stats).to receive(:new).and_return(stats)

      get "/system_health", headers: admin_headers, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body).to include("checked_at", "coap_listener", "sidekiq", "database")
      expect(body["sidekiq"]).to include("enqueued", "processed", "failed", "processes")
    end

    context "with format.html" do
      it "renders HTML dashboard for system health" do
        get "/system_health",
            headers: { "Authorization" => "Bearer #{admin_token}", "Accept" => "text/html" }
        expect(response).to have_http_status(:ok)
        expect(response.content_type).to include("text/html")
      end
    end
  end
end
