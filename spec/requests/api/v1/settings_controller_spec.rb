# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::SettingsController, type: :request do
  let(:organization) { create(:organization) }
  let(:admin_user) { create(:user, :admin, organization: organization) }
  let(:regular_user) { create(:user, organization: organization) }
  let(:admin_token) { admin_user.generate_token_for(:api_access) }
  let(:regular_token) { regular_user.generate_token_for(:api_access) }
  let(:admin_headers) { { "Authorization" => "Bearer #{admin_token}" } }
  let(:regular_headers) { { "Authorization" => "Bearer #{regular_token}" } }

  describe "GET /api/v1/settings" do
    it "returns organization settings for admin users" do
      get "/api/v1/settings", headers: admin_headers, as: :json
      expect(response).to have_http_status(:ok)

      body = response.parsed_body
      expect(body["organization"]["name"]).to eq(organization.name)
      expect(body["organization"]["billing_email"]).to eq(organization.billing_email)
    end

    it "returns 403 for non-admin users" do
      get "/api/v1/settings", headers: regular_headers, as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "PATCH /api/v1/settings" do
    it "updates organization settings for admin users" do
      patch "/api/v1/settings",
            headers: admin_headers,
            params: { organization: { name: "New Forest Fund", billing_email: "new@example.org" } },
            as: :json

      expect(response).to have_http_status(:ok)
      organization.reload
      expect(organization.name).to eq("New Forest Fund")
      expect(organization.billing_email).to eq("new@example.org")
    end

    it "returns 403 for non-admin users" do
      patch "/api/v1/settings",
            headers: regular_headers,
            params: { organization: { name: "Hacked" } },
            as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end
end
