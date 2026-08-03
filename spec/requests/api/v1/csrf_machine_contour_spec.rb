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
  # Механіка, на якій стоїть перевірка: БЕЗумовний `skip_forgery_protection`
  # прибирає `verify_authenticity_token` із ланцюга зовсім, а УМОВНИЙ (`only:`)
  # лишає його на місці з `unless`-фільтром. Отже присутність колбека і є
  # підписом «скоуп звужений».
  describe "звуження skip'а — не косметика" do
    def forgery_callback?(controller)
      controller._process_action_callbacks.map(&:filter).include?(:verify_authenticity_token)
    end

    it "m2m_auth ЛИШАЄ захист поза :create (бо refresh приймає cookie-сесію)" do
      expect(forgery_callback?(Api::V1::M2mAuthController)).to be(true),
        "skip_forgery_protection у m2m_auth мусить бути `only: :create` — інакше " \
        "разом із машинним входом відкривається браузерний `refresh`"
    end

    it "суто машинні контролери звільнені повністю" do
      expect(forgery_callback?(Api::V1::OracleCallbacksController)).to be(false)
      expect(forgery_callback?(Api::V1::HeliumSosController)).to be(false)
    end
  end
end
