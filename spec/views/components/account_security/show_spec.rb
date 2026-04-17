# frozen_string_literal: true

require "rails_helper"

RSpec.describe AccountSecurity::Show do
  def mock_user(mfa_enabled: false, recovery_codes_remaining: 10, password_digest: nil)
    u = OpenStruct.new(
      mfa_enabled: mfa_enabled,
      recovery_codes_remaining: recovery_codes_remaining,
      password_digest: password_digest
    )
    u.define_singleton_method(:mfa_enabled?) { mfa_enabled }
    u
  end

  def mock_identity(provider: "google_oauth2", uid: "1234567890abc", primary: false,
                    locked: false, active: true)
    i = OpenStruct.new(
      provider: provider,
      uid: uid,
      primary: primary,
      locked_at: locked ? 1.hour.ago : nil
    )
    i.define_singleton_method(:locked?) { locked }
    i.define_singleton_method(:primary?) { primary }
    i.define_singleton_method(:active?) { active }
    i.define_singleton_method(:model_name) { ActiveModel::Name.new(Identity) }
    i.define_singleton_method(:to_key) { [1] }
    i.define_singleton_method(:to_param) { "1" }
    i
  end

  def render_component(user:, identities:)
    ApplicationController.renderer.render(
      component_class.new(user: user, identities: identities),
      layout: false
    )
  end

  let(:user) { mock_user }
  let(:identities) { [] }
  let(:html) { render_component(user: user, identities: identities) }

  describe "MFA section" do
    it "renders the Two-Factor Authentication heading" do
      expect(html).to include("Two-Factor Authentication")
    end

    it "shows MFA disabled warning when mfa is off" do
      expect(html).to include("MFA вимкнено")
    end

    it "shows MFA enabled status when mfa is active" do
      user_with_mfa = mock_user(mfa_enabled: true, recovery_codes_remaining: 8)
      html = render_component(user: user_with_mfa, identities: identities)
      expect(html).to include("MFA увімкнено")
    end

    it "shows recovery codes count when mfa enabled" do
      user_with_mfa = mock_user(mfa_enabled: true, recovery_codes_remaining: 8)
      html = render_component(user: user_with_mfa, identities: identities)
      expect(html).to include("8")
    end
  end

  describe "toggle button" do
    it "renders Enable MFA button when mfa is disabled" do
      expect(html).to include("Enable MFA")
    end

    it "renders Disable MFA button when mfa is enabled" do
      user_with_mfa = mock_user(mfa_enabled: true)
      html = render_component(user: user_with_mfa, identities: identities)
      expect(html).to include("Disable MFA")
    end
  end

  describe "password form" do
    it "renders Password heading" do
      expect(html).to include("Password")
    end

    it "renders new_password field" do
      expect(html).to include('name="new_password"')
    end

    it "renders new_password_confirmation field" do
      expect(html).to include('name="new_password_confirmation"')
    end

    it "renders current_password field when password is set" do
      user_with_pwd = mock_user(password_digest: "hashed_secret")
      html = render_component(user: user_with_pwd, identities: identities)
      expect(html).to include('name="current_password"')
    end

    it "shows Set Password button when no password" do
      expect(html).to include("Set Password")
    end

    it "shows Change Password button when password already set" do
      user_with_pwd = mock_user(password_digest: "hashed_secret")
      html = render_component(user: user_with_pwd, identities: identities)
      expect(html).to include("Change Password")
    end
  end

  describe "linked identities" do
    let(:identity) { mock_identity(provider: "google_oauth2", uid: "1234567890abcdef0", primary: true) }
    let(:html) { render_component(user: user, identities: [identity]) }

    it "renders Linked Identity Providers heading" do
      expect(html).to include("Linked Identity Providers")
    end

    it "renders the provider name" do
      expect(html).to include("Google Oauth2")
    end

    it "renders the Primary badge for primary identities" do
      expect(html).to include("Primary")
    end

    it "renders the UID (truncated)" do
      expect(html).to include("1234567890abc")
    end
  end

  describe "lock/unlock buttons" do
    it "renders Lock button for an unlocked identity" do
      identity = mock_identity(locked: false)
      html = render_component(user: user, identities: [identity])
      expect(html).to include("Lock")
    end

    it "renders Unlock button for a locked identity" do
      identity = mock_identity(locked: true)
      html = render_component(user: user, identities: [identity])
      expect(html).to include("Unlock")
    end
  end

  describe "available providers" do
    it "renders available providers not yet linked" do
      identity = mock_identity(provider: "google_oauth2")
      html = render_component(user: user, identities: [identity])
      expect(html).to include("Link Facebook")
    end

    it "does not show a provider if already linked" do
      identity = mock_identity(provider: "google_oauth2")
      html = render_component(user: user, identities: [identity])
      expect(html).not_to include("Link Google Oauth2")
    end
  end
end
