# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::PasswordsController, type: :request do
  let(:organization) { create(:organization) }
  let(:user) { create(:user, organization: organization, password: "password12345") }

  # =========================================================================
  # GET /api/v1/forgot_password
  # =========================================================================
  describe "GET /api/v1/forgot_password" do
    it "renders the forgot password page" do
      get "/api/v1/forgot_password"
      expect(response).to have_http_status(:ok)
    end
  end

  # =========================================================================
  # POST /api/v1/forgot_password
  # =========================================================================
  describe "POST /api/v1/forgot_password" do
    it "returns success message for existing email (anti-enumeration)" do
      post "/api/v1/forgot_password", params: { email: user.email_address }, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["message"]).to include("email існує")
    end

    it "returns the same success message for non-existing email (anti-enumeration)" do
      post "/api/v1/forgot_password", params: { email: "ghost@silken.net" }, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["message"]).to include("email існує")
    end

    it "enqueues a password reset email for existing users" do
      expect {
        post "/api/v1/forgot_password", params: { email: user.email_address }, as: :json
      }.to have_enqueued_mail(PasswordMailer, :reset_instructions)
    end

    it "does not enqueue email for non-existing users" do
      expect {
        post "/api/v1/forgot_password", params: { email: "ghost@silken.net" }, as: :json
      }.not_to have_enqueued_mail(PasswordMailer, :reset_instructions)
    end
  end

  # =========================================================================
  # GET /api/v1/reset_password
  # =========================================================================
  describe "GET /api/v1/reset_password" do
    it "renders the reset password form" do
      token = user.generate_token_for(:password_reset)
      get "/api/v1/reset_password", params: { token: token }
      expect(response).to have_http_status(:ok)
    end
  end

  # =========================================================================
  # PATCH /api/v1/reset_password
  # =========================================================================
  describe "PATCH /api/v1/reset_password" do
    it "resets the password with a valid token" do
      token = user.generate_token_for(:password_reset)

      patch "/api/v1/reset_password", params: {
        token: token,
        password: "new_password_123",
        password_confirmation: "new_password_123"
      }, as: :json

      expect(response).to have_http_status(:ok)
      expect(user.reload.authenticate("new_password_123")).to be_truthy
    end

    it "rejects an expired/invalid token" do
      patch "/api/v1/reset_password", params: {
        token: "invalid-token",
        password: "new_password_123",
        password_confirmation: "new_password_123"
      }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "rejects password shorter than 12 characters" do
      token = user.generate_token_for(:password_reset)

      patch "/api/v1/reset_password", params: {
        token: token,
        password: "short",
        password_confirmation: "short"
      }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to include("12")
    end

    it "rejects mismatched password confirmation" do
      token = user.generate_token_for(:password_reset)

      patch "/api/v1/reset_password", params: {
        token: token,
        password: "new_password_123",
        password_confirmation: "different_password"
      }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to include("не співпадають")
    end

    context "format.html responses" do
      it "renders short password error as HTML" do
        token = user.generate_token_for(:password_reset)

        patch "/api/v1/reset_password",
          params: { token: token, password: "short", password_confirmation: "short" },
          headers: { "Accept" => "text/html" }

        expect(response).to have_http_status(:ok)
      end

      it "renders mismatched password error as HTML" do
        token = user.generate_token_for(:password_reset)

        patch "/api/v1/reset_password",
          params: { token: token, password: "new_password_123", password_confirmation: "different" },
          headers: { "Accept" => "text/html" }

        expect(response).to have_http_status(:ok)
      end
    end
  end
end
