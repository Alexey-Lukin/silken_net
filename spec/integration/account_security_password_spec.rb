# SPDX-License-Identifier: AGPL-3.0-or-later
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
    # [S6.21] Toggle-enable шле в setup-флоу; сам по собі він прапорця не
    # піднімає, тож ПОВЕРХНЯ СТАТУСУ, яку читають три споживачі, лишається
    # чесною і після спроби.
    it "PATCH /account_security/mfa cannot enable MFA, and the status surface stays honest" do
      patch "/account_security/mfa",
            headers: { "Authorization" => "Bearer #{token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:conflict)

      get "/account_security",
          headers: { "Authorization" => "Bearer #{token}", "Accept" => "application/json" }

      json = response.parsed_body
      expect(json["mfa_enabled"]).to be false
      expect(json["recovery_codes_remaining"]).to eq(0)
    end

    it "PATCH /account_security/mfa disables MFA when already enabled (with step-up password)" do
      user.update!(otp_required_for_login: true, recovery_codes: [ "code1", "code2" ])

      patch "/account_security/mfa",
            params: { current_password: "securepass1234" },
            headers: { "Authorization" => "Bearer #{token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["mfa_enabled"]).to be false
    end

    it "PATCH /account_security/password changes password" do
      patch "/account_security/password",
            params: {
              current_password: "securepass1234",
              new_password: "newsecurepass12",
              new_password_confirmation: "newsecurepass12"
            },
            headers: { "Authorization" => "Bearer #{token}", "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      expect(user.reload.authenticate("newsecurepass12")).to be_truthy
    end

    it "rejects mismatched password confirmation" do
      patch "/account_security/password",
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
    it "POST /forgot_password sends reset email" do
      mailer_double = instance_double(ActionMailer::MessageDelivery, deliver_later: nil)
      mailer_with = double(reset_instructions: mailer_double) # rubocop:disable RSpec/VerifiedDoubles -- проксі від `.with(...)` віддає ActionMailer::Parameterized::Mailer, а той не ВИЗНАЧАЄ mailer-методів (method_missing) — verifying double їх не бачить за побудовою; звірено `public_method_defined?`
      allow(PasswordMailer).to receive(:with).and_return(mailer_with)

      post "/forgot_password",
           params: { email: user.email_address },
           headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["message"]).to include("email")
    end

    it "PATCH /reset_password updates password with valid token" do
      reset_token = user.generate_token_for(:password_reset)

      patch "/reset_password",
            params: {
              token: reset_token,
              password: "newpassword1234",
              password_confirmation: "newpassword1234"
            },
            headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      expect(user.reload.authenticate("newpassword1234")).to be_truthy
    end
  end
end
