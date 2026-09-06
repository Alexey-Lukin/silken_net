# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::NotificationsController, type: :request do
  let(:organization) { create(:organization) }
  let(:user) { create(:user, organization: organization) }
  let(:api_token) { user.generate_token_for(:api_access) }
  let(:headers) { { "Authorization" => "Bearer #{api_token}" } }

  describe "GET /notifications/settings" do
    it "returns the current notification channel settings" do
      get "/notifications/settings", headers: headers, as: :json
      expect(response).to have_http_status(:ok)

      body = response.parsed_body
      expect(body["channels"]["email"]).to eq(user.email_address)
      expect(body["channels"]).to have_key("push_token")
      # [ARCH.78] SMS відкинуто присудом — API не сміє рекламувати канал.
      expect(body["channels"]).not_to have_key("phone")
    end
  end

  # ⛔ `describe "PATCH /notifications/settings"` ВИДАЛЕНО 2026-09-06 [ARCH.60]:
  # екшен і маршрут знято разом із поверхнею збору `push_token`. Приклади стерегли
  # саме їх; лишити їх означало б тримати спеку, що звертається до неіснуючого
  # маршруту (404), тобто червону за побудовою, а не доказову.
  # ⊕ GET-гілка нижче лишається — читання стану не є збором.

  context "with format.html responses" do
    let(:html_headers) do
      { "Authorization" => "Bearer #{user.generate_token_for(:api_access)}", "Accept" => "text/html" }
    end

    it "renders HTML for settings" do
      get "/notifications/settings", headers: html_headers
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/html")
    end

    # ⛔ `it "renders HTML for update_settings error"` ВИДАЛЕНО 2026-09-06 [ARCH.60]
    # разом з екшеном. ⚠️ Приклад ніс ДВІ осі, і обидві названі тут, щоб зникнення
    # було видимим: [SEC.25] «422 — дзеркало JSON-гілки, бо на 200 Turbo відповідь
    # викидає» і [I18N.1] «причину видно, і імʼя поля приходить з `attributes.*`».
    # Перша вісь має носіїв на інших мультиформатних екшенах; друга лишається без
    # піна — ціна названа в `spec/views/components/notifications/settings_spec.rb`.
  end
end
