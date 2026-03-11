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
      expect(body["channels"]).to have_key("push_token")
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

    it "updates push_token" do
      patch "/api/v1/notifications/settings",
            headers: headers,
            params: { push_token: "fcm_token_abc123" },
            as: :json

      expect(response).to have_http_status(:ok)
      user.reload
      expect(user.push_token).to eq("fcm_token_abc123")
      expect(response.parsed_body["channels"]["push_token"]).to eq("fcm_token_abc123")
    end

    it "returns unprocessable_content when update fails with invalid params" do
      patch "/api/v1/notifications/settings",
            headers: headers,
            params: { phone_number: "0123" },
            as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["errors"]).to be_present
    end
  end

  context "with format.html responses" do
    let(:html_headers) do
      { "Authorization" => "Bearer #{user.generate_token_for(:api_access)}", "Accept" => "text/html" }
    end

    it "renders HTML for settings" do
      get "/api/v1/notifications/settings", headers: html_headers
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/html")
    end

    it "renders HTML for update_settings error" do
      patch "/api/v1/notifications/settings",
            headers: html_headers,
            params: { phone_number: "0123" }

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/html")
    end
  end
end
