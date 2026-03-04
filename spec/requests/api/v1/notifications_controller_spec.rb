# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::NotificationsController, type: :request do
  let(:organization) { create(:organization) }
  let(:user) { create(:user, organization: organization, phone_number: "+380501234567", telegram_chat_id: "12345") }
  let(:api_token) { user.generate_token_for(:api_access) }
  let(:headers) { { "Authorization" => "Bearer #{api_token}" } }

  describe "GET /api/v1/notifications/settings" do
    it "returns the current notification channel settings" do
      get "/api/v1/notifications/settings", headers: headers, as: :json
      expect(response).to have_http_status(:ok)

      body = response.parsed_body
      expect(body["channels"]["email"]).to eq(user.email_address)
      expect(body["channels"]["phone"]).to eq("+380501234567")
      expect(body["channels"]["telegram_chat_id"]).to eq("12345")
    end
  end

  describe "PATCH /api/v1/notifications/settings" do
    it "updates notification channel settings" do
      patch "/api/v1/notifications/settings",
            headers: headers,
            params: { phone_number: "+380509876543", telegram_chat_id: "99999" },
            as: :json

      expect(response).to have_http_status(:ok)
      user.reload
      expect(user.phone_number).to eq("+380509876543")
      expect(user.telegram_chat_id).to eq("99999")
    end
  end
end
