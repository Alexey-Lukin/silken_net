# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Users::Profile do
  # [TEST.12] Реальні незбережені записи, а не `OpenStruct`: мок оголошував
  # `role` рядком і сам вигадував `full_name`/`mfa_enabled?`, тож роле-предикат
  # (`admin_or_above?`) у ньому не існував — і рядкове порівняння `role == "admin"`,
  # що казало super_admin'ові «доступ обмежений», сюїта виразити не могла.
  def mock_user(first_name: "Olena", last_name: "Kovalenko",
                email_address: "olena@example.org", role: "admin",
                id: 42, mfa_enabled: true, password_digest: "hashed",
                last_seen_at: 5.minutes.ago, organization_name: "Forest Fund")
    User.new(
      id: id,
      first_name: first_name,
      last_name: last_name,
      email_address: email_address,
      role: role,
      password_digest: password_digest,
      otp_required_for_login: mfa_enabled,
      last_seen_at: last_seen_at,
      organization: organization_name && Organization.new(name: organization_name)
    )
  end

  def mock_identity(provider: "google_oauth2", primary: false)
    Identity.new(provider: provider, primary: primary)
  end

  def render_component(user:, maintenance_count: 0, active_identities: [])
    ApplicationController.renderer.render(
      component_class.new(user: user, maintenance_count: maintenance_count, active_identities: active_identities),
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

    it "falls back to the email's first character when first_name is nil" do
      no_name_user = mock_user(first_name: nil)
      no_name_user.email_address = "zed@example.org"
      rendered = render_component(user: no_name_user)
      expect(rendered).to include(">z<")
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

  describe "access privileges" do
    it "shows the fallback none-label when the user has no organization" do
      rendered = render_component(user: mock_user(organization_name: nil))
      expect(rendered).to include("None")
    end

    it "shows Limited command execution for a non-admin role" do
      rendered = render_component(user: mock_user(role: "forester"))
      expect(rendered).to include("Limited")
    end

    # [UI.10] Рядкове порівняння `role == "admin"` казало super_admin'ові, що
    # його доступ обмежений — тобто екран стверджував про глядача те, що модель
    # спростовує (`admin_or_above?`).
    it "shows Full command execution for a super_admin, who is above admin" do
      rendered = render_component(user: mock_user(role: "super_admin"))
      expect(rendered).to include("Full")
      expect(rendered).not_to include("Limited")
    end
  end

  describe "activity stats" do
    it "shows NEVER SEEN when the user has never been seen" do
      rendered = render_component(user: mock_user(last_seen_at: nil))
      expect(rendered).to include("NEVER SEEN")
    end

    # [UI.10] Мітка називається «Last Sync» — вона питає ЧАС. Доти в комірці
    # стояв ВЕРДИКТ, обчислений як `last_seen_at.present?`, тож акаунт річної
    # давнини лишався «ONLINE» назавжди. Рецидив цієї форми червонить цей пін.
    it "renders when the user was last seen, not a verdict about being online" do
      rendered = render_component(user: mock_user(last_seen_at: 1.year.ago))

      expect(rendered).to include("year")
      expect(rendered).not_to include("ONLINE")
    end

    it "renders a fresh visit as a recent relative time" do
      rendered = render_component(user: mock_user(last_seen_at: 5.minutes.ago))
      expect(rendered).to include("5 minutes ago")
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

    it "shows Not Set when password_digest is nil" do
      no_pwd = mock_user(password_digest: nil)
      rendered = render_component(user: no_pwd)
      expect(rendered).to include("Not Set")
    end

    it "renders Manage link to account security" do
      expect(html).to include("Manage →")
    end
  end

  describe "linked identities list" do
    context "with identities" do
      let(:identity) { mock_identity(provider: "google_oauth2", primary: true) }
      let(:html) { render_component(user: user, active_identities: [ identity ]) }

      it "renders Linked Identity Providers heading" do
        expect(html).to include("Linked Identity Providers")
      end

      it "renders the provider name" do
        expect(html).to include("Google")
        expect(html).not_to include("Google Oauth2")
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
      html = render_component(user: user, active_identities: [ identity ])
      # «LinkedIn», не «Linkedin»: `.titleize` ламав саме власну назву бренду.
      expect(html).to include("LinkedIn")
    end

    it "renders provider badge for twitter" do
      identity = mock_identity(provider: "twitter")
      html = render_component(user: user, active_identities: [ identity ])
      expect(html).to include("Twitter")
    end

    it "renders provider badge for facebook with blue icon" do
      identity = mock_identity(provider: "facebook")
      html = render_component(user: user, active_identities: [ identity ])
      expect(html).to include("Facebook")
      expect(html).to include("🟦")
    end

    it "renders generic link icon for unknown provider" do
      identity = mock_identity(provider: "github")
      html = render_component(user: user, active_identities: [ identity ])
      expect(html).to include("🔗")
    end
  end
end
