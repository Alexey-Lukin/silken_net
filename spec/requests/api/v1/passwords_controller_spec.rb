# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::PasswordsController, type: :request do
  let(:organization) { create(:organization) }
  let(:user) { create(:user, organization: organization, password: "password12345") }

  # =========================================================================
  # GET /forgot_password
  # =========================================================================
  describe "GET /forgot_password" do
    it "renders the forgot password page" do
      get "/forgot_password"
      expect(response).to have_http_status(:ok)
    end
  end

  # =========================================================================
  # POST /forgot_password
  # =========================================================================
  describe "POST /forgot_password" do
    it "returns success message for existing email (anti-enumeration)" do
      post "/forgot_password", params: { email: user.email_address }, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["message"]).to include("email exists")
    end

    it "returns the same success message for non-existing email (anti-enumeration)" do
      post "/forgot_password", params: { email: "ghost@silkennet.com" }, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["message"]).to include("email exists")
    end

    it "enqueues a password reset email for existing users" do
      expect {
        post "/forgot_password", params: { email: user.email_address }, as: :json
      }.to have_enqueued_mail(PasswordMailer, :reset_instructions)
    end

    it "does not enqueue email for non-existing users" do
      expect {
        post "/forgot_password", params: { email: "ghost@silkennet.com" }, as: :json
      }.not_to have_enqueued_mail(PasswordMailer, :reset_instructions)
    end
  end

  # =========================================================================
  # GET /reset_password
  # =========================================================================
  describe "GET /reset_password" do
    # 🔴 [TEST.12 вісь D] Пін доти був самим `:ok`, а несуче тут — ПРОВОДКА токена:
    # контролер бере його з `params` і кладе в приховане поле, звідки він і їде
    # назад у `PATCH`. Розрив цього ланцюга лишає сторінку цілком справною на
    # вигляд (200, форма, кнопка) і робить скидання пароля мовчки неможливим —
    # сабміт піде без токена. Компонентна спека це не ловить: вона подає токен
    # сама, тобто перевіряє шаблон, а не те, що контролер його прокинув.
    it "прокидає токен із запиту в приховане поле форми" do
      token = user.generate_token_for(:password_reset)

      get "/reset_password", params: { token: token }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(name="token" value="#{token}"))
    end
  end

  # =========================================================================
  # PATCH /reset_password
  # =========================================================================
  describe "PATCH /reset_password" do
    it "resets the password with a valid token" do
      token = user.generate_token_for(:password_reset)

      patch "/reset_password", params: {
        token: token,
        password: "new_password_123",
        password_confirmation: "new_password_123"
      }, as: :json

      expect(response).to have_http_status(:ok)
      expect(user.reload.authenticate("new_password_123")).to be_truthy
    end

    # 🔴 [TEST.12 вісь D] Три приклади нижче доти доводили лише КОД, а тракт тут
    # НЕавтентифікований — тобто обхід перевірки токена (найдорожча з можливих
    # регресій цього файлу) віддав би 422 і лишився зеленим під назвою «rejects».
    # Указала знову асиметрія: позитивний приклад свій наслідок звіряє, негативні
    # не звіряли жодного. Пін тримає обидва боки — старий пароль ще діє, новий ні.
    it "rejects an expired/invalid token" do
      # ⚠️ `user` МУСИТЬ існувати до запиту, і це не формальність: `let` лінивий,
      # тож доти запис народжувався аж у ассерті — вже з правильним паролем — і
      # пін підтверджував сам себе, хай би що робив контролер. Спіймано мутацією,
      # яка ПРОЙШЛА: підміна резолву токена на `|| User.first` лишила сюїту зеленою.
      user

      patch "/reset_password", params: {
        token: "invalid-token",
        password: "new_password_123",
        password_confirmation: "new_password_123"
      }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(user.reload.authenticate("password12345")).to be_truthy
      expect(user.reload.authenticate("new_password_123")).to be_falsey
    end

    it "rejects password shorter than 12 characters" do
      token = user.generate_token_for(:password_reset)

      patch "/reset_password", params: {
        token: token,
        password: "short",
        password_confirmation: "short"
      }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to include("12")
      expect(user.reload.authenticate("password12345")).to be_truthy
    end

    it "rejects mismatched password confirmation" do
      token = user.generate_token_for(:password_reset)

      patch "/reset_password", params: {
        token: token,
        password: "new_password_123",
        password_confirmation: "different_password"
      }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to include("do not match")
      expect(user.reload.authenticate("password12345")).to be_truthy
      expect(user.reload.authenticate("new_password_123")).to be_falsey
    end

    context "with HTML format" do
      it "handles short password in HTML format" do
        token = user.generate_token_for(:password_reset)

        patch "/reset_password", params: {
          token: token,
          password: "short",
          password_confirmation: "short"
        }, headers: { "Accept" => "text/html" }

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "handles mismatched passwords in HTML format" do
        token = user.generate_token_for(:password_reset)

        patch "/reset_password", params: {
          token: token,
          password: "new_password_123",
          password_confirmation: "different_password"
        }, headers: { "Accept" => "text/html" }

        expect(response).to have_http_status(:unprocessable_content)
      end

      # 🔴 [UI.7] Ці три приклади доти твердили РІВНО `have_http_status(:redirect)`, тобто
      # «будь-який 3xx у будь-яку адресу» — і два перші є ДВІЙНИКАМИ з протилежними
      # цілями (`login_path` після успішної зміни ⊥ `forgot_password_path` на битому
      # токені). Отже успіх і провал скидання пароля сюїта не розрізняла ВЗАГАЛІ: обидва
      # лишались зеленими, якби контролер повів людину не туди. Пін тепер називає ціль,
      # а успіх додатково пінить НАСЛІДОК — сам пароль, — бо редирект у правильне місце
      # ще не означає, що щось змінилось (§B.2 #21).
      it "redirects to the login page and actually changes the password" do
        token = user.generate_token_for(:password_reset)

        patch "/reset_password", params: {
          token: token,
          password: "new_password_123",
          password_confirmation: "new_password_123"
        }, headers: { "Accept" => "text/html" }

        expect(response).to redirect_to(login_path)
        expect(user.reload.authenticate("new_password_123")).to be_truthy
      end

      it "sends an invalid token BACK to the forgot form, and changes nothing" do
        patch "/reset_password", params: {
          token: "invalid-token",
          password: "new_password_123",
          password_confirmation: "new_password_123"
        }, headers: { "Accept" => "text/html" }

        expect(response).to redirect_to(forgot_password_path)
        expect(user.reload.authenticate("new_password_123")).to be_falsey
      end

      it "redirects an HTML forgot_password submit to the login page" do
        post "/forgot_password", params: { email: user.email_address },
          headers: { "Accept" => "text/html" }

        expect(response).to redirect_to(login_path)
      end
    end
  end

  describe "rate limit" do
    it "returns 429 after exceeding rate limit for JSON format" do
      Prosopite.pause if defined?(Prosopite)
      4.times do
        post "/forgot_password", params: { email: user.email_address }, as: :json
      end

      expect(response).to have_http_status(:too_many_requests)
    ensure
      Prosopite.resume if defined?(Prosopite)
    end

    # [TEST.10] Тут статус приймався множиною {302, 303, 429}, і вимір показав,
    # що вона не могла впасти НІКОЛИ й з двох незалежних причин. (1) `429` для
    # HTML недосяжний за дизайном: обробник `rate_limit` віддає JSON-гілці 429, а
    # HTML-гілці — редірект. (2) Успішний сабміт ТЕЖ редіректить, тож сам по собі
    # `302` не відрізняє «ліміт спрацював» від «ліміт не спрацював». Різнить їх
    # ЦІЛЬ (`forgot_password_path` проти `login_path`) і флеш — саме їх і треба
    # тверджувати. ⚠️ Ліміт тут контролерний (`rate_limit to: 3`), НЕ
    # `rack_attack` «logins/ip» на 10 — плутати їх означає рахувати не ті запити.
    it "redirects back to the form with a rate-limit notice once the HTML limit is hit" do
      Prosopite.pause if defined?(Prosopite)
      3.times do
        post "/forgot_password", params: { email: user.email_address }, as: :json
      end

      post "/forgot_password",
        params: { email: user.email_address },
        headers: { "Accept" => "text/html" }

      expect(response).to have_http_status(:found)
      expect(response).to redirect_to(forgot_password_path)
      expect(flash[:error]).to eq("Too many attempts. Try again in 5 minutes.")
    ensure
      Prosopite.resume if defined?(Prosopite)
    end
  end

  describe "HTML error paths" do
    it "renders flash for short password in HTML format" do
      token = user.generate_token_for(:password_reset)

      patch "/reset_password",
        params: { token: token, password: "short", password_confirmation: "short" },
        headers: { "Accept" => "text/html" }

      # [SEC.25/TEST.10] Статус приймався множиною {200, 500} — твердження, що не
      # може впасти. 422 тут несучий: на `200` без редиректу Turbo викидає відповідь,
      # тобто людина, що скидає пароль, не бачила ЖОДНОЇ реакції на закороткий.
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(I18n.t("passwords.reset.too_short"))
    end

    it "renders flash for mismatched passwords in HTML format" do
      token = user.generate_token_for(:password_reset)

      patch "/reset_password",
        params: { token: token, password: "new_password_123", password_confirmation: "different_123" },
        headers: { "Accept" => "text/html" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(I18n.t("passwords.reset.mismatch"))
    end
  end
end
