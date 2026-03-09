# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Account security and password management" do
  let(:organization) { create(:organization) }
  let(:user) { create(:user, organization: organization, password: "securepass1234") }
  let(:token) { user.generate_token_for(:api_access) }

  # ---------------------------------------------------------------------------
  # AccountSecurityController
  # ---------------------------------------------------------------------------
  describe "Account Security API" do
    it "GET /api/v1/account_security shows MFA status and identities" do
      identity = create(:identity, user: user, provider: "google_oauth2")

      get "/api/v1/account_security",
          headers: { "Authorization" => "Bearer #{token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["mfa_enabled"]).to be false
      expect(json["identities"].length).to eq(1)
      expect(json["identities"].first["provider"]).to eq("google_oauth2")
    end

    it "PATCH /api/v1/account_security/mfa enables MFA with recovery codes" do
      patch "/api/v1/account_security/mfa",
            headers: { "Authorization" => "Bearer #{token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["mfa_enabled"]).to be true
      expect(json["recovery_codes"]).to be_present
    end

    it "PATCH /api/v1/account_security/mfa disables MFA when already enabled" do
      user.update!(otp_required_for_login: true, recovery_codes: [ "code1", "code2" ])

      patch "/api/v1/account_security/mfa",
            headers: { "Authorization" => "Bearer #{token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["mfa_enabled"]).to be false
    end

    it "DELETE /api/v1/account_security/identities/:id unlinks provider" do
      identity = create(:identity, user: user)

      delete "/api/v1/account_security/identities/#{identity.id}",
             headers: { "Authorization" => "Bearer #{token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      expect(Identity.find_by(id: identity.id)).to be_nil
    end

    it "prevents unlinking last identity without password" do
      user.update_columns(password_digest: nil)
      identity = create(:identity, user: user)

      delete "/api/v1/account_security/identities/#{identity.id}",
             headers: { "Authorization" => "Bearer #{token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(Identity.find_by(id: identity.id)).to be_present
    end

    it "PATCH lock/unlock identity" do
      identity = create(:identity, user: user)

      patch "/api/v1/account_security/identities/#{identity.id}/lock",
            headers: { "Authorization" => "Bearer #{token}", "Accept" => "application/json" }
      expect(response).to have_http_status(:ok)
      expect(identity.reload.locked?).to be true

      patch "/api/v1/account_security/identities/#{identity.id}/unlock",
            headers: { "Authorization" => "Bearer #{token}", "Accept" => "application/json" }
      expect(response).to have_http_status(:ok)
      expect(identity.reload.locked?).to be false
    end

    it "PATCH /api/v1/account_security/password changes password" do
      patch "/api/v1/account_security/password",
            params: {
              current_password: "securepass1234",
              new_password: "newsecurepass12",
              new_password_confirmation: "newsecurepass12"
            },
            headers: { "Authorization" => "Bearer #{token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      expect(user.reload.authenticate("newsecurepass12")).to be_truthy
    end

    it "rejects wrong current password" do
      patch "/api/v1/account_security/password",
            params: {
              current_password: "wrong_password",
              new_password: "newsecurepass12",
              new_password_confirmation: "newsecurepass12"
            },
            headers: { "Authorization" => "Bearer #{token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "rejects too-short new password" do
      patch "/api/v1/account_security/password",
            params: {
              current_password: "securepass1234",
              new_password: "short",
              new_password_confirmation: "short"
            },
            headers: { "Authorization" => "Bearer #{token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "rejects mismatched password confirmation" do
      patch "/api/v1/account_security/password",
            params: {
              current_password: "securepass1234",
              new_password: "newsecurepass12",
              new_password_confirmation: "different_pass12"
            },
            headers: { "Authorization" => "Bearer #{token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  # ---------------------------------------------------------------------------
  # PasswordsController
  # ---------------------------------------------------------------------------
  describe "Password Reset API" do
    it "POST /api/v1/forgot_password sends reset email" do
      mailer_double = double(deliver_later: nil)
      mailer_with = double(reset_instructions: mailer_double)
      allow(PasswordMailer).to receive(:with).and_return(mailer_with)

      post "/api/v1/forgot_password",
           params: { email: user.email_address },
           headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["message"]).to include("email")
    end

    it "POST /api/v1/forgot_password protects against email enumeration" do
      post "/api/v1/forgot_password",
           params: { email: "nonexistent@example.com" },
           headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
    end

    it "PATCH /api/v1/reset_password updates password with valid token" do
      reset_token = user.generate_token_for(:password_reset)

      patch "/api/v1/reset_password",
            params: {
              token: reset_token,
              password: "newpassword1234",
              password_confirmation: "newpassword1234"
            },
            headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      expect(user.reload.authenticate("newpassword1234")).to be_truthy
    end

    it "PATCH /api/v1/reset_password rejects invalid token" do
      patch "/api/v1/reset_password",
            params: { token: "invalid_token", password: "newpassword1234", password_confirmation: "newpassword1234" },
            headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "PATCH /api/v1/reset_password rejects short password" do
      reset_token = user.generate_token_for(:password_reset)

      patch "/api/v1/reset_password",
            params: { token: reset_token, password: "short", password_confirmation: "short" },
            headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "PATCH /api/v1/reset_password rejects mismatched confirmation" do
      reset_token = user.generate_token_for(:password_reset)

      patch "/api/v1/reset_password",
            params: { token: reset_token, password: "newpassword1234", password_confirmation: "different1234" },
            headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  # ---------------------------------------------------------------------------
  # Identity model
  # ---------------------------------------------------------------------------
  describe "Identity lifecycle" do
    it "locks and unlocks an identity" do
      identity = create(:identity, user: user)
      identity.lock!
      expect(identity.locked?).to be true

      identity.unlock!
      expect(identity.locked?).to be false
    end

    it "makes identity primary" do
      id1 = create(:identity, user: user, primary: true)
      id2 = create(:identity, :apple, user: user, primary: false)

      id2.make_primary!
      expect(id2.reload.primary?).to be true
      expect(id1.reload.primary?).to be false
    end

    it "checks token_expired?" do
      identity = create(:identity, user: user, expires_at: 1.hour.from_now)
      expect(identity.token_expired?).to be false

      identity.update!(expires_at: 1.hour.ago)
      expect(identity.token_expired?).to be true
    end
  end
end
