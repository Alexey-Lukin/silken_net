# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# 🔴 [SEC.30] Гард осі, якої вся решта сюїти НЕ БАЧИТЬ ЗА ПОБУДОВОЮ.
#
# `config/environments/test.rb` вимикає `allow_forgery_protection` — тобто рівно той
# прапорець, що створює дефект. Тому кожна наявна webhook-спека зелена й доводить
# HMAC-логіку, до якої прод НЕ ДОХОДИВ: `protect_from_forgery with: :exception`
# лишав `verify_authenticity_token` у ланцюгу, а `handle_unverified_request`
# пропускає лише Bearer — тож машинний запит із HMAC/Ed25519 у ТІЛІ падав
# `InvalidAuthenticityToken` → `rescue_from StandardError` → 500 ще до свого гарда.
#
# Уражені були ТРИ входи, і третій знайшовся лише свіпом класу: `oracle_callbacks`
# (mint-money-path), `helium_sos` (аварійний крик Королеви) і `m2m_auth#create`
# (видача токенів шлюзам — без нього M2M не працювала взагалі).
#
# ⚠️ Тому цей файл САМ вмикає прапорець. Пін на «доходить до гарда» (401/404),
# а не на «не 500»: перше падає при знятті `skip_forgery_protection`, друге
# лишилось би зеленим на будь-якій іншій поломці.
RSpec.describe "CSRF на машинному контурі", type: :request do
  around do |example|
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    example.run
  ensure
    ActionController::Base.allow_forgery_protection = original
  end

  describe "POST /api/v1/oracle_callbacks" do
    let(:body) { { chainlink_request_id: "req-1", success: true }.to_json }

    around do |example|
      old = ENV["CHAINLINK_HMAC_SECRET"]
      ENV["CHAINLINK_HMAC_SECRET"] = "oracle-shared-secret"
      example.run
    ensure
      ENV["CHAINLINK_HMAC_SECRET"] = old
    end

    it "доходить до HMAC-гарда, а не падає на CSRF" do
      post "/api/v1/oracle_callbacks",
           params: body,
           headers: { "CONTENT_TYPE" => "application/json", "X-Chainlink-Signature" => "0" * 64 }

      # 401 = відповів ГАРД. 500 означало б, що CSRF перехопив раніше.
      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["error"]).to eq("Invalid HMAC signature")
    end
  end

  describe "POST /api/v1/telemetry/helium" do
    let(:body) { { dev_eui: "AABBCCDDEEFF0011", payload: Base64.strict_encode64("x" * 12) }.to_json }

    around do |example|
      old = ENV["HELIUM_WEBHOOK_SECRET"]
      ENV["HELIUM_WEBHOOK_SECRET"] = "helium-shared-secret"
      example.run
    ensure
      ENV["HELIUM_WEBHOOK_SECRET"] = old
    end

    it "доходить до HMAC-гарда, а не падає на CSRF" do
      post "/api/v1/telemetry/helium",
           params: body,
           headers: { "CONTENT_TYPE" => "application/json", "X-Helium-Signature" => "0" * 64 }

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["error"]).to eq("Invalid signature")
    end
  end

  describe "POST /api/v1/auth/m2m_token" do
    it "доходить до пошуку пристрою, а не падає на CSRF" do
      post "/api/v1/auth/m2m_token",
           params: { did: "SNET-Q-DEADBEEF", timestamp: Time.current.to_i, signature: "00" }.to_json,
           headers: { "CONTENT_TYPE" => "application/json" }

      # 404 = дійшли до `HardwareKey.find_by` — тобто контролер ВИКОНАВСЯ.
      expect(response).to have_http_status(:not_found)
    end
  end

  # 🔴 Негативний контроль: без нього піни вище доводили б лише «CSRF нікого не
  # турбує», і глобальне зняття захисту лишило б їх зеленими.
  #
  # ⚠️ Доти тут стояла СТРУКТУРНА перевірка — «колбек присутній у ланцюгу» — з
  # поясненням «присутність і є підписом „скоуп звужений"». Це неправда [SEC.31]:
  # `skip_callback` з умовою не видаляє колбек, а підміняє його умовним близнюком
  # із тим самим символом, тож перевірка була однаково зелена для правильного
  # `only: :create` і для ІНВЕРСІЇ `only: :refresh`, яка відкриває саме
  # cookie-досяжну дію. Обсяг зняття тепер пінить `browser_contour_json_spec`
  # порівнянням множин; тут лишається те, чого структурний гейт не вміє — реальний
  # HTTP-запит із увімкненим forgery-protection, тобто ДРУГА, незалежна вісь.
  describe "звуження skip'а — не косметика" do
    it "refresh (cookie-досяжний) НЕ доходить до контролера без CSRF-токена" do
      post "/api/v1/auth/m2m_token/refresh",
           params: {}.to_json,
           headers: { "CONTENT_TYPE" => "application/json" }

      # `handle_unverified_request` пропускає лише Bearer; тут його нема, тож
      # запит гине на CSRF ще до `authenticate_user!`. Саме це й означає, що
      # зняття НЕ накрило `refresh`.
      expect(response).to have_http_status(:internal_server_error)
    end
  end
end
