# frozen_string_literal: true

require "rails_helper"

RSpec.describe "User authentication and session lifecycle" do
  let(:organization) { create(:organization) }

  describe "User model token generation" do
    let(:user) { create(:user, organization: organization) }

    it "generates api_access token" do
      token = user.generate_token_for(:api_access)
      expect(token).to be_present

      found = User.find_by_token_for(:api_access, token)
      expect(found).to eq(user)
    end

    it "generates password_reset token" do
      token = user.generate_token_for(:password_reset)
      expect(token).to be_present

      found = User.find_by_token_for(:password_reset, token)
      expect(found).to eq(user)
    end

    it "generates email_verification token" do
      token = user.generate_token_for(:email_verification)
      expect(token).to be_present
    end
  end

  describe "User roles and access levels" do
    it "investor has read_only access" do
      user = create(:user, :investor, organization: organization)
      expect(user.role).to eq("investor")
      expect(user.access_level).to eq("read_only")
    end

    it "admin has organization access" do
      user = create(:user, :admin, organization: organization)
      expect(user.role).to eq("admin")
      expect(user.access_level).to eq("organization")
    end

    it "super_admin has system access" do
      user = create(:user, :super_admin, organization: organization)
      expect(user.role).to eq("super_admin")
      expect(user.access_level).to eq("system")
    end

    it "forester has field access" do
      user = create(:user, :forester, organization: organization)
      expect(user.role).to eq("forester")
      expect(user.access_level).to eq("field")
    end
  end

  describe "User MFA and recovery codes" do
    let(:user) { create(:user, organization: organization) }

    it "generates recovery codes" do
      codes = user.generate_recovery_codes!
      expect(codes).to be_an(Array)
      expect(codes.length).to eq(10)
      codes.each { |code| expect(code).to match(/\A[a-f0-9]+\z/i) }
    end

    it "consumes a recovery code" do
      codes = user.generate_recovery_codes!
      first_code = codes.first

      expect(user.consume_recovery_code!(first_code)).to be true
      expect(user.consume_recovery_code!(first_code)).to be false # Already used
    end

    it "rejects invalid recovery code" do
      user.generate_recovery_codes!
      expect(user.consume_recovery_code!("invalid_code")).to be false
    end
  end

  describe "User validations" do
    it "requires email" do
      user = build(:user, email: nil, organization: organization)
      expect(user).not_to be_valid
      expect(user.errors[:email]).to be_present
    end

    it "requires minimum password length" do
      user = build(:user, password: "short", organization: organization)
      expect(user).not_to be_valid
    end

    it "normalizes email to lowercase" do
      user = create(:user, email: "Test@Example.COM", organization: organization)
      expect(user.email).to eq("test@example.com")
    end

    it "validates phone number format (E.164)" do
      user = build(:user, phone_number: "123", organization: organization)
      expect(user).not_to be_valid if user.phone_number.present?
    end
  end

  describe "API authentication flow via requests" do
    let(:user) { create(:user, :admin, organization: organization) }
    let(:token) { user.generate_token_for(:api_access) }
    let(:headers) { { "Authorization" => "Bearer #{token}", "Accept" => "application/json" } }

    it "authenticates with valid bearer token" do
      get "/api/v1/users/me", headers: headers
      expect(response).to have_http_status(:ok)

      json = response.parsed_body
      expect(json["data"]["email"]).to eq(user.email)
    end

    it "rejects invalid bearer token" do
      get "/api/v1/users/me", headers: { "Authorization" => "Bearer invalid_token", "Accept" => "application/json" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects missing authorization header" do
      get "/api/v1/users/me", headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "Session-based authentication" do
    let(:user) { create(:user, organization: organization) }

    it "creates session on login" do
      post "/api/v1/login", params: { email: user.email, password: "password12345" }
      expect(response).to have_http_status(:redirect).or have_http_status(:ok)
    end

    it "rejects invalid credentials" do
      post "/api/v1/login", params: { email: user.email, password: "wrong_password" },
                            headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "User helper methods" do
    it "full_name concatenates first and last name" do
      user = create(:user, first_name: "Олексій", last_name: "Лукін", organization: organization)
      expect(user.full_name).to eq("Олексій Лукін")
    end

    it "super_admin? returns true for super admins" do
      user = create(:user, :super_admin, organization: organization)
      expect(user.super_admin?).to be true
    end

    it "organization_admin? returns true for admins" do
      user = create(:user, :admin, organization: organization)
      expect(user.organization_admin?).to be true
    end

    it "touch_visit! updates last_visit_at" do
      user = create(:user, organization: organization)
      user.touch_visit!
      expect(user.reload.last_visit_at).to be_present
    end
  end
end
