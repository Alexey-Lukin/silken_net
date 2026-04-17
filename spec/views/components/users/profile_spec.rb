# frozen_string_literal: true

require "rails_helper"

RSpec.describe Users::Profile do
  def mock_user(first_name: "Olena", last_name: "Kovalenko",
                email_address: "olena@example.org", role: "admin",
                id: 42, mfa_enabled: true, password_digest: "hashed",
                last_seen_at: 5.minutes.ago, organization_name: "Forest Fund")
    org = OpenStruct.new(name: organization_name)
    u = OpenStruct.new(
      first_name: first_name,
      last_name: last_name,
      email_address: email_address,
      role: role,
      id: id,
      password_digest: password_digest,
      last_seen_at: last_seen_at,
      organization: org
    )
    u.define_singleton_method(:mfa_enabled?) { mfa_enabled }
    u.define_singleton_method(:full_name) { "#{first_name} #{last_name}" }
    u
  end

  def mock_identity(provider: "google_oauth2", primary: false, active: true)
    i = OpenStruct.new(provider: provider, primary: primary)
    i.define_singleton_method(:primary?) { primary }
    i.define_singleton_method(:active?) { active }
    i
  end

  def render_component(user:, maintenance_count: 0, active_identities: [])
    ApplicationController.renderer.render(
      described_class.new(user: user, maintenance_count: maintenance_count, active_identities: active_identities),
      layout: false
    )
  end

  let(:user) { mock_user }
  let(:html) { render_component(user: user, maintenance_count: 5) }

  describe "avatar with initial" do
    it "renders the first letter of first_name as avatar" do
      expect(html).to include("O")
    end

    it "renders the user avatar container" do
      expect(html).to include("h-32 w-32")
    end
  end

  describe "full_name display" do
    it "renders the full name" do
      expect(html).to include("Olena Kovalenko")
    end
  end

  describe "email display" do
    it "renders the email address" do
      expect(html).to include("olena@example.org")
    end
  end

  describe "role badge" do
    it "renders the role badge" do
      expect(html).to include("ADMIN")
    end

    it "renders the user ID badge" do
      expect(html).to include("#42")
    end
  end

  describe "maintenance count" do
    it "renders the maintenance record count" do
      expect(html).to include("Records")
      expect(html).to include("5")
    end
  end

  describe "security status indicators" do
    it "renders Security Status heading" do
      expect(html).to include("Security Status")
    end

    it "renders 2FA/MFA indicator" do
      expect(html).to include("2FA")
    end

    it "shows Active for enabled MFA" do
      expect(html).to include("Active")
    end

    it "shows Disabled for disabled MFA" do
      user_no_mfa = mock_user(mfa_enabled: false)
      html = render_component(user: user_no_mfa)
      expect(html).to include("Disabled")
    end

    it "renders Password indicator" do
      expect(html).to include("Password")
    end

    it "shows Set when password is present" do
      expect(html).to include("Set")
    end

    it "renders Manage link to account security" do
      expect(html).to include("Manage →")
    end
  end

  describe "linked identities list" do
    context "with identities" do
      let(:identity) { mock_identity(provider: "google_oauth2", primary: true) }
      let(:html) { render_component(user: user, active_identities: [identity]) }

      it "renders Linked Identity Providers heading" do
        expect(html).to include("Linked Identity Providers")
      end

      it "renders the provider name" do
        expect(html).to include("Google Oauth2")
      end

      it "renders Primary badge for primary identity" do
        expect(html).to include("Primary")
      end
    end

    context "without identities" do
      it "does not render the linked providers section" do
        html = render_component(user: user, active_identities: [])
        expect(html).not_to include("Linked Identity Providers")
      end
    end
  end

  describe "provider badges" do
    it "renders provider badge for linkedin" do
      identity = mock_identity(provider: "linkedin")
      html = render_component(user: user, active_identities: [identity])
      expect(html).to include("Linkedin")
    end

    it "renders provider badge for twitter" do
      identity = mock_identity(provider: "twitter")
      html = render_component(user: user, active_identities: [identity])
      expect(html).to include("Twitter")
    end
  end
end
