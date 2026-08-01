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
      post "/forgot_password", params: { email: "ghost@silken.net" }, as: :json
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
        post "/forgot_password", params: { email: "ghost@silken.net" }, as: :json
      }.not_to have_enqueued_mail(PasswordMailer, :reset_instructions)
    end
  end

  # =========================================================================
  # GET /reset_password
  # =========================================================================
  describe "GET /reset_password" do
    it "renders the reset password form" do
      token = user.generate_token_for(:password_reset)
      get "/reset_password", params: { token: token }
      expect(response).to have_http_status(:ok)
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

    it "rejects an expired/invalid token" do
      patch "/reset_password", params: {
        token: "invalid-token",
        password: "new_password_123",
        password_confirmation: "new_password_123"
      }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
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

      it "redirects on successful HTML password reset" do
        token = user.generate_token_for(:password_reset)

        patch "/reset_password", params: {
          token: token,
          password: "new_password_123",
          password_confirmation: "new_password_123"
        }, headers: { "Accept" => "text/html" }

        expect(response).to have_http_status(:redirect)
      end

      it "redirects when token is invalid in HTML format" do
        patch "/reset_password", params: {
          token: "invalid-token",
          password: "new_password_123",
          password_confirmation: "new_password_123"
        }, headers: { "Accept" => "text/html" }

        expect(response).to have_http_status(:redirect)
      end

      it "redirects on HTML forgot_password submit" do
        post "/forgot_password", params: { email: user.email_address },
          headers: { "Accept" => "text/html" }

        expect(response).to have_http_status(:redirect)
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

    it "redirects after exceeding rate limit for HTML format" do
      Prosopite.pause if defined?(Prosopite)
      3.times do
        post "/forgot_password", params: { email: user.email_address }, as: :json
      end

      post "/forgot_password",
        params: { email: user.email_address },
        headers: { "Accept" => "text/html" }

      expect(response.status).to be_in([ 302, 303, 429 ])
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

      # [SEC.25/TEST.10] Було `be_in([200, 500])` — твердження, що не може
      # впасти. 422 тут несучий: на `200` без редиректу Turbo викидає відповідь,
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
