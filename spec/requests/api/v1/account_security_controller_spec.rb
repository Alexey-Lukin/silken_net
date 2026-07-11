# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::AccountSecurityController, type: :request do
  let(:organization) { create(:organization) }
  let(:user) { create(:user, organization: organization, password: "password12345") }
  let(:token) { user.generate_token_for(:api_access) }
  let(:headers) { { "Authorization" => "Bearer #{token}" } }

  # =========================================================================
  # GET /api/v1/account_security
  # =========================================================================
  describe "GET /api/v1/account_security" do
    it "returns security status as JSON" do
      get "/api/v1/account_security", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body

      expect(body).to include("mfa_enabled", "recovery_codes_remaining", "has_password", "identities")
      expect(body["mfa_enabled"]).to be false
      expect(body["has_password"]).to be true
    end

    it "returns 401 without authentication" do
      get "/api/v1/account_security", as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "lists linked identities" do
      create(:identity, user: user, provider: "google_oauth2")
      create(:identity, :facebook, user: user)

      get "/api/v1/account_security", headers: headers, as: :json

      identities = response.parsed_body["identities"]
      expect(identities.size).to eq(2)
      expect(identities.map { |i| i["provider"] }).to contain_exactly("google_oauth2", "facebook")
    end

    it "renders the HTML dashboard page" do
      get "/api/v1/account_security", headers: headers
      expect(response).to have_http_status(:ok)
    end
  end

  # =========================================================================
  # PATCH /api/v1/account_security/mfa — Toggle MFA
  # =========================================================================
  describe "PATCH /api/v1/account_security/mfa" do
    it "enables MFA and returns recovery codes" do
      patch "/api/v1/account_security/mfa", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["mfa_enabled"]).to be true
      expect(body["recovery_codes"]).to be_an(Array)
      expect(body["recovery_codes"].size).to eq(10)

      expect(user.reload.otp_required_for_login).to be true
    end

    it "disables MFA when already enabled (with valid current_password)" do
      user.update!(otp_required_for_login: true, recovery_codes: %w[a b c].to_json)

      patch "/api/v1/account_security/mfa",
            params: { current_password: "password12345" },
            headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["mfa_enabled"]).to be false
      expect(user.reload.otp_required_for_login).to be false
      expect(user.recovery_codes).to be_nil
    end

    # =========================================================================
    # STEP-UP AUTH: disabling MFA is a security downgrade, so require a fresh
    # password proof. Tests below pin both the "deny" and "allow" branches.
    # =========================================================================
    it "rejects MFA disable when current_password is wrong" do
      user.update!(otp_required_for_login: true, recovery_codes: %w[a b c].to_json)

      patch "/api/v1/account_security/mfa",
            params: { current_password: "wrong-password" },
            headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(user.reload.otp_required_for_login).to be true
    end

    it "rejects MFA disable when current_password is missing" do
      user.update!(otp_required_for_login: true, recovery_codes: %w[a b c].to_json)

      patch "/api/v1/account_security/mfa", headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(user.reload.otp_required_for_login).to be true
    end

    it "allows MFA disable without password challenge when user is OAuth-only (no password_digest)" do
      user.update!(otp_required_for_login: true, recovery_codes: %w[a b c].to_json)
      user.update_columns(password_digest: nil)

      patch "/api/v1/account_security/mfa", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(user.reload.otp_required_for_login).to be false
    end
  end

  # =========================================================================
  # PATCH /api/v1/account_security/password — Change Password
  # =========================================================================
  describe "PATCH /api/v1/account_security/password" do
    it "changes password with correct current password" do
      patch "/api/v1/account_security/password", headers: headers, params: {
        current_password: "password12345",
        new_password: "new_secure_pass_1",
        new_password_confirmation: "new_secure_pass_1"
      }, as: :json

      expect(response).to have_http_status(:ok)
      expect(user.reload.authenticate("new_secure_pass_1")).to be_truthy
    end

    it "rejects wrong current password" do
      patch "/api/v1/account_security/password", headers: headers, params: {
        current_password: "wrong_password",
        new_password: "new_secure_pass_1",
        new_password_confirmation: "new_secure_pass_1"
      }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "rejects too short new password" do
      patch "/api/v1/account_security/password", headers: headers, params: {
        current_password: "password12345",
        new_password: "short",
        new_password_confirmation: "short"
      }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to include("12")
    end

    it "rejects mismatched confirmation" do
      patch "/api/v1/account_security/password", headers: headers, params: {
        current_password: "password12345",
        new_password: "new_secure_pass_1",
        new_password_confirmation: "different_password"
      }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "allows setting password without current_password when user has no password (OAuth-only)" do
      # Simulate OAuth-only user (no password digest)
      user.update_columns(password_digest: nil)

      patch "/api/v1/account_security/password", headers: headers, params: {
        new_password: "first_password_1",
        new_password_confirmation: "first_password_1"
      }, as: :json

      expect(response).to have_http_status(:ok)
      expect(user.reload.authenticate("first_password_1")).to be_truthy
    end

    # =========================================================================
    # SESSION REVOCATION: a password change is a security event — other
    # sessions on stolen devices must be invalidated, the current session
    # must survive so the user is not bounced out of the dashboard mid-flow.
    # =========================================================================
    context "with session revocation on password change" do
      let!(:other_session) do
        user.sessions.create!(
          ip_address: "10.0.0.99",
          user_agent: "AnotherDevice/1.0"
        )
      end

      let!(:current_request_session) do
        user.sessions.create!(
          ip_address: "127.0.0.1",
          user_agent: "Rails Testing"
        )
      end

      it "revokes other sessions and keeps the matching IP+UA session alive" do
        # Match the Rack test default IP/UA to current_request_session
        patch "/api/v1/account_security/password",
              headers: headers.merge("User-Agent" => current_request_session.user_agent),
              params: {
                current_password: "password12345",
                new_password: "fresh_secure_pass_1",
                new_password_confirmation: "fresh_secure_pass_1"
              }, as: :json

        expect(response).to have_http_status(:ok)
        expect(Session.find_by(id: other_session.id)).to be_nil
        expect(Session.find_by(id: current_request_session.id)).to be_present
      end

      it "falls back to keeping the newest session row when IP+UA does not match" do
        # No IP/UA match → fallback keeps the newest row (current_request_session
        # is the most recently created and therefore preserved).
        patch "/api/v1/account_security/password",
              headers: headers.merge("User-Agent" => "MismatchedClient/3.0"),
              params: {
                current_password: "password12345",
                new_password: "fresh_secure_pass_2",
                new_password_confirmation: "fresh_secure_pass_2"
              }, as: :json

        expect(response).to have_http_status(:ok)
        # The fallback keeps the newest row regardless of IP/UA.
        surviving_ids = user.sessions.pluck(:id)
        expect(surviving_ids).to eq([ current_request_session.id ])
      end
    end

    # [SEC.16] Cookie-сесія salt-bound: раніше dashboard-auth читав голий
    # session[:user_id] і викрадений cookie переживав password-reset 14 днів.
    context "with a salt-bound dashboard cookie [SEC.16]" do
      it "invalidates a stale cookie after the password changes elsewhere" do
        post "/api/v1/login", params: { email: user.email_address, password: "password12345" }

        get "/api/v1/account_security"
        expect(response).to have_http_status(:ok)

        # Зміна пароля «з іншого пристрою» (поза цим cookie-jar)
        user.update!(password: "hijack-survivor-pass-1")

        get "/api/v1/account_security"
        expect(response).to have_http_status(:unauthorized)
      end

      it "rejects a cookie whose user no longer exists" do
        post "/api/v1/login", params: { email: user.email_address, password: "password12345" }

        user.sessions.delete_all
        user.reload.destroy!

        get "/api/v1/account_security"
        expect(response).to have_http_status(:unauthorized)
      end

      it "keeps the initiating session alive across its own password change" do
        post "/api/v1/login", params: { email: user.email_address, password: "password12345" }

        patch "/api/v1/account_security/password",
              params: {
                current_password: "password12345",
                new_password: "fresh_secure_pass_3",
                new_password_confirmation: "fresh_secure_pass_3"
              }, as: :json
        expect(response).to have_http_status(:ok)

        get "/api/v1/account_security"
        expect(response).to have_http_status(:ok)
      end
    end
  end

  # =========================================================================
  # DELETE /api/v1/account_security/identities/:id — Unlink Identity
  # =========================================================================
  describe "DELETE /api/v1/account_security/identities/:id" do
    it "unlinks an identity when user has a password" do
      identity = create(:identity, user: user, provider: "google_oauth2")

      delete "/api/v1/account_security/identities/#{identity.id}", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(Identity.find_by(id: identity.id)).to be_nil
    end

    it "prevents unlinking last identity when user has no password" do
      user.update_columns(password_digest: nil)
      identity = create(:identity, user: user, provider: "google_oauth2")

      delete "/api/v1/account_security/identities/#{identity.id}", headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(Identity.find_by(id: identity.id)).to be_present
    end

    it "allows unlinking one identity when user has multiple (no password)" do
      user.update_columns(password_digest: nil)
      google = create(:identity, user: user, provider: "google_oauth2")
      _facebook = create(:identity, :facebook, user: user)

      delete "/api/v1/account_security/identities/#{google.id}", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(Identity.find_by(id: google.id)).to be_nil
    end
  end

  # =========================================================================
  # PATCH /api/v1/account_security/identities/:id/lock — Lock Identity
  # =========================================================================
  describe "PATCH /api/v1/account_security/identities/:id/lock" do
    it "locks an identity" do
      identity = create(:identity, user: user)

      patch "/api/v1/account_security/identities/#{identity.id}/lock", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(identity.reload.locked?).to be true
    end
  end

  # =========================================================================
  # PATCH /api/v1/account_security/identities/:id/unlock — Unlock Identity
  # =========================================================================
  describe "PATCH /api/v1/account_security/identities/:id/unlock" do
    it "unlocks a locked identity" do
      identity = create(:identity, :locked, user: user)

      patch "/api/v1/account_security/identities/#{identity.id}/unlock", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(identity.reload.locked?).to be false
    end
  end
end
