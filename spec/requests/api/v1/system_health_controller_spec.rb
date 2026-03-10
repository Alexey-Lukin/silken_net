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

  describe "GET /api/v1/system_health" do
    it "returns system health status for admin users" do
      get "/api/v1/system_health", headers: admin_headers, as: :json
      expect(response).to have_http_status(:ok)

      body = response.parsed_body
      expect(body).to include("checked_at", "coap_listener", "sidekiq", "database")
      expect(body["coap_listener"]).to include("alive", "port")
      expect(body["database"]).to include("connected")
    end

    it "returns 403 for non-admin users" do
      get "/api/v1/system_health", headers: regular_headers, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "handles Sidekiq stats errors gracefully" do
      allow(Sidekiq::Stats).to receive(:new).and_raise(RuntimeError, "Connection refused")

      get "/api/v1/system_health", headers: admin_headers, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["sidekiq"]).to have_key("error")
    end

    it "handles database connection failures gracefully" do
      allow(ActiveRecord::Base.connection).to receive(:active?).and_raise(RuntimeError, "could not connect")

      get "/api/v1/system_health", headers: admin_headers, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["database"]["connected"]).to be(false)
      expect(body["database"]).to have_key("error")
    end

    it "returns all expected top-level keys in the response" do
      stats = instance_double(Sidekiq::Stats, enqueued: 0, processed: 100, failed: 2, workers_size: 4, queues: {})
      allow(Sidekiq::Stats).to receive(:new).and_return(stats)

      get "/api/v1/system_health", headers: admin_headers, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body).to include("checked_at", "coap_listener", "sidekiq", "database")
      expect(body["sidekiq"]).to include("enqueued", "processed", "failed")
    end
  end
end
