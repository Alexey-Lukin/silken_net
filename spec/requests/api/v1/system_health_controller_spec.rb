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
  end
end
