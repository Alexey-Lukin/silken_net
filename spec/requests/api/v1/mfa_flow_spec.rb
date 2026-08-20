# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [S6.21] Наскрізний контур другого фактора: setup-флоу (секрет → QR → verify →
# прапорець) і verify-on-login (пароль → pending → TOTP/recovery → сесія).
#
# Піни тут — на НАСЛІДКАХ (сесія існує/не існує, прапорець піднявся/ні, код
# спожито), не на статусах: 303 однаковий і в успіху, і в половині відмов.
RSpec.describe "MFA flow", type: :request do
  let(:organization) { create(:organization) }
  let(:password) { "correct-horse-battery" }
  let(:user) { create(:user, organization: organization, password: password, password_confirmation: password) }

  def sign_in!(as_user: user, with_password: password)
    post "/login", params: { email: as_user.email_address, password: with_password }
  end

  describe "setup flow" do
    before { sign_in! }

    it "provisions a secret, renders the QR page and activates only on a fresh valid code" do
      post "/account_security/mfa_setup"
      expect(response).to redirect_to("/account_security/mfa_setup")

      follow_redirect!
      expect(response.body).to include("otpauth://").or include("svg")

      user.reload
      expect(user.otp_secret).to be_present
      expect(user.mfa_enabled?).to be(false)

      patch "/account_security/mfa_setup", params: { otp_code: ROTP::TOTP.new(user.otp_secret).now }

      user.reload
      expect(user.mfa_enabled?).to be(true)
      # Rotation при активації: свіжий повний набір recovery-кодів.
      expect(user.recovery_codes_remaining).to eq(10)
    end

    it "does not raise the flag on a wrong code" do
      post "/account_security/mfa_setup"

      patch "/account_security/mfa_setup", params: { otp_code: "000000" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(user.reload.mfa_enabled?).to be(false)
    end

    it "refuses a second setup while MFA is already enabled" do
      post "/account_security/mfa_setup"
      patch "/account_security/mfa_setup", params: { otp_code: ROTP::TOTP.new(user.reload.otp_secret).now }
      old_secret = user.reload.otp_secret

      post "/account_security/mfa_setup"

      expect(response).to redirect_to("/account_security")
      expect(user.reload.otp_secret).to eq(old_secret)

      # JSON-гілка тієї ж відмови — 409 із машинним текстом, не редирект.
      post "/account_security/mfa_setup", as: :json
      expect(response).to have_http_status(:conflict)
    end

    it "sends a bare GET without a provisioned secret back to account security" do
      get "/account_security/mfa_setup"
      expect(response).to redirect_to("/account_security")
    end

    it "bounces every setup verb off an already-enabled account" do
      post "/account_security/mfa_setup"
      patch "/account_security/mfa_setup", params: { otp_code: ROTP::TOTP.new(user.reload.otp_secret).now }

      get "/account_security/mfa_setup"
      expect(response).to redirect_to("/account_security")

      patch "/account_security/mfa_setup", params: { otp_code: "000000" }
      expect(response).to redirect_to("/account_security")
      expect(user.reload.mfa_enabled?).to be(true)
    end

    it "sends a PATCH without a provisioned secret back to account security" do
      patch "/account_security/mfa_setup", params: { otp_code: "123456" }
      expect(response).to redirect_to("/account_security")
    end

    it "serves the JSON halves of activation (success and mismatch)" do
      post "/account_security/mfa_setup"

      patch "/account_security/mfa_setup", params: { otp_code: "000000" }, as: :json
      expect(response).to have_http_status(:unprocessable_content)

      patch "/account_security/mfa_setup",
            params: { otp_code: ROTP::TOTP.new(user.reload.otp_secret).now }, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["mfa_enabled"]).to be(true)
    end
  end

  describe "verify-on-login" do
    let(:mfa_user) do
      create(:user, organization: organization, password: password, password_confirmation: password,
                    otp_secret: ROTP::Base32.random, otp_required_for_login: true).tap(&:generate_recovery_codes!)
    end

    it "does NOT establish a session on password alone — the flag is finally read at login" do
      sign_in!(as_user: mfa_user)

      expect(response).to redirect_to("/login/mfa")
      # Найгостріший пін пункту: пароль більше не дає доступу (401 —
      # render_unauthorized малює логін НА МІСЦІ, редиректу в цьому тракті нема).
      get "/dashboard"
      expect(response).to have_http_status(:unauthorized)
    end

    it "completes login with a valid TOTP code" do
      sign_in!(as_user: mfa_user)
      post "/login/mfa", params: { otp_code: ROTP::TOTP.new(mfa_user.otp_secret).now }

      expect(response).to redirect_to("/dashboard")
      get "/dashboard"
      expect(response).to have_http_status(:ok)
    end

    it "rejects a wrong code and leaves no session behind" do
      sign_in!(as_user: mfa_user)
      post "/login/mfa", params: { otp_code: "000000" }

      expect(response).to have_http_status(:unauthorized)
      get "/dashboard"
      expect(response).to have_http_status(:unauthorized)
    end

    # Анти-replay: перехоплений код не дає ДРУГОГО входу всередині вікна.
    it "rejects the same TOTP code replayed after a successful login" do
      code = ROTP::TOTP.new(mfa_user.otp_secret).now
      sign_in!(as_user: mfa_user)
      post "/login/mfa", params: { otp_code: code }
      expect(response).to redirect_to("/dashboard")

      delete "/logout"
      sign_in!(as_user: mfa_user)
      post "/login/mfa", params: { otp_code: code }

      expect(response).to have_http_status(:unauthorized)
    end

    it "accepts a recovery code exactly once and burns it" do
      code = JSON.parse(mfa_user.recovery_codes).first
      sign_in!(as_user: mfa_user)
      post "/login/mfa", params: { recovery_code: code }

      expect(response).to redirect_to("/dashboard")
      expect(mfa_user.reload.recovery_codes_remaining).to eq(9)

      delete "/logout"
      sign_in!(as_user: mfa_user)
      post "/login/mfa", params: { recovery_code: code }

      expect(response).to have_http_status(:unauthorized)
    end

    it "expires the pending challenge after the TTL and sends the visitor back to login" do
      sign_in!(as_user: mfa_user)

      travel (Api::V1::MfaChallengesController::PENDING_TTL + 1.minute) do
        post "/login/mfa", params: { otp_code: ROTP::TOTP.new(mfa_user.otp_secret).now }
        expect(response).to redirect_to("/login")
      end
    end

    it "sends a visitor with no pending challenge back to login" do
      get "/login/mfa"
      expect(response).to redirect_to("/login")
    end

    it "renders the challenge form for a live pending visitor" do
      sign_in!(as_user: mfa_user)
      follow_redirect!

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('name="otp_code"')
    end

    # JSON-клієнт: половини входу не існує і для нього.
    it "answers a JSON login with 401 mfa_required instead of half a session" do
      post "/login", params: { email: mfa_user.email_address, password: password }, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["code"]).to eq("mfa_required")
      expect(response.parsed_body).not_to have_key("token")
    end
  end

  describe "toggle after the build" do
    before { sign_in! }

    it "sends the enable direction into the setup flow instead of raising the flag blindly" do
      patch "/account_security/mfa", params: {}

      expect(response).to redirect_to("/account_security/mfa_setup")
      expect(user.reload.mfa_enabled?).to be(false)
    end
  end

  # [S6.21] Одноразовий reveal recovery-набору + ротація. Піни — на НАСЛІДКАХ і
  # на ВМІСТІ (кожен код із БД у тілі): redirect-ціль однакова для успіху reveal
  # і для відмови без маркера, тож сам статус тут не дискримінує нічого.
  describe "recovery-code reveal and rotation" do
    before { sign_in! }

    def activate_mfa!
      post "/account_security/mfa_setup"
      patch "/account_security/mfa_setup", params: { otp_code: ROTP::TOTP.new(user.reload.otp_secret).now }
    end

    it "shows the full set exactly once after activation, then never again" do
      activate_mfa!
      expect(response).to redirect_to("/account_security/mfa_recovery_codes")

      follow_redirect!
      expect(response).to have_http_status(:ok)
      codes = user.reload.parsed_recovery_codes
      # Ліхтар на популяцію: пін «кожен код у тілі» вакуумний на порожньому наборі.
      expect(codes.size).to eq(10)
      codes.each { |code| expect(response.body).to include(code) }

      # Показ РІВНО РАЗ: маркер знято першим рендером — закладка/Back мовчить.
      get "/account_security/mfa_recovery_codes"
      expect(response).to redirect_to("/account_security")
    end

    it "refuses a bare GET without the one-time marker and leaks no codes" do
      activate_mfa!
      # Свіжа сесія того ж користувача (маркер живе в cookie активаційної сесії).
      # travel: анти-replay не пускає код активаційного 30-с слота на вхід.
      travel 31.seconds do
        delete "/logout"
        sign_in!
        post "/login/mfa", params: { otp_code: ROTP::TOTP.new(user.reload.otp_secret).now }
        expect(response).to redirect_to("/dashboard")

        get "/account_security/mfa_recovery_codes"
        expect(response).to redirect_to("/account_security")
      end
    end

    it "sends a non-MFA account away without generating anything" do
      get "/account_security/mfa_recovery_codes"
      expect(response).to redirect_to("/account_security")
      expect(user.reload.recovery_codes).to be_nil

      post "/account_security/mfa_recovery_codes", params: { current_password: password }
      expect(response).to redirect_to("/account_security")
      expect(user.reload.recovery_codes).to be_nil
    end

    it "rotates the set behind a step-up and reveals the NEW codes once" do
      activate_mfa!
      old_codes = user.reload.parsed_recovery_codes

      post "/account_security/mfa_recovery_codes", params: { current_password: password }
      expect(response).to redirect_to("/account_security/mfa_recovery_codes")

      new_codes = user.reload.parsed_recovery_codes
      expect(new_codes.size).to eq(10)
      # Старий набір знецінено ЦІЛКОМ, не поповнено.
      expect(new_codes & old_codes).to be_empty

      follow_redirect!
      new_codes.each { |code| expect(response.body).to include(code) }
    end

    it "does NOT rotate on a wrong current password" do
      activate_mfa!
      before_codes = user.reload.parsed_recovery_codes

      post "/account_security/mfa_recovery_codes", params: { current_password: "wrong-password" }

      # Пін на НАСЛІДОК: набір недоторканий (redirect їде і в успіху, і у відмові).
      expect(user.reload.parsed_recovery_codes).to eq(before_codes)
    end

    it "hands the JSON client its set inside the activation and rotation responses" do
      post "/account_security/mfa_setup"
      patch "/account_security/mfa_setup",
            params: { otp_code: ROTP::TOTP.new(user.reload.otp_secret).now }, as: :json

      activation_codes = response.parsed_body["recovery_codes"]
      expect(activation_codes).to match_array(user.reload.parsed_recovery_codes)

      post "/account_security/mfa_recovery_codes", params: { current_password: password }, as: :json
      expect(response).to have_http_status(:ok)
      rotated = response.parsed_body["recovery_codes"]
      expect(rotated).to match_array(user.reload.parsed_recovery_codes)
      expect(rotated & activation_codes).to be_empty
    end
  end
end
