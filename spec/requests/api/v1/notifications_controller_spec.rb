# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::NotificationsController, type: :request do
  let(:organization) { create(:organization) }
  let(:user) { create(:user, organization: organization, telegram_chat_id: "12345") }
  let(:api_token) { user.generate_token_for(:api_access) }
  let(:headers) { { "Authorization" => "Bearer #{api_token}" } }

  describe "GET /notifications/settings" do
    it "returns the current notification channel settings" do
      get "/notifications/settings", headers: headers, as: :json
      expect(response).to have_http_status(:ok)

      body = response.parsed_body
      expect(body["channels"]["email"]).to eq(user.email_address)
      expect(body["channels"]["telegram_chat_id"]).to eq("12345")
      expect(body["channels"]).to have_key("push_token")
      # [ARCH.78] SMS відкинуто присудом — API не сміє рекламувати канал.
      expect(body["channels"]).not_to have_key("phone")
    end
  end

  describe "PATCH /notifications/settings" do
    it "updates notification channel settings" do
      patch "/notifications/settings",
            headers: headers,
            params: { telegram_chat_id: "99999" },
            as: :json

      expect(response).to have_http_status(:ok)
      user.reload
      expect(user.telegram_chat_id).to eq("99999")
    end

    it "updates push_token" do
      patch "/notifications/settings",
            headers: headers,
            params: { push_token: "fcm_token_abc123" },
            as: :json

      expect(response).to have_http_status(:ok)
      user.reload
      expect(user.push_token).to eq("fcm_token_abc123")
      expect(response.parsed_body["channels"]["push_token"]).to eq("fcm_token_abc123")
    end

    it "returns unprocessable_content when update fails with invalid params" do
      patch "/notifications/settings",
            headers: headers,
            params: { telegram_chat_id: "not-a-chat" },
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
      get "/notifications/settings", headers: html_headers
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/html")
    end

    it "renders HTML for update_settings error" do
      patch "/notifications/settings",
            headers: html_headers,
            params: { telegram_chat_id: "not-a-chat" }

      # [SEC.25] 422 — дзеркало JSON-гілки; на 200 Turbo відповідь викидає, тож
      # невалідний chat_id не показував користувачеві нічого.
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.content_type).to include("text/html")

      # 🔴 І друга половина: коментар вище казав «не показував нічого», але після
      # фіксу статусу сторінка все одно мовчала — компонент не мав куди покласти
      # причину. Пін на статус цього не бачив за побудовою.
      expect(response.body).to include(I18n.t("errors.api.validation_failed_title"))
      expect(response.body).to include("Telegram chat ID is invalid")
    end
  end
end
