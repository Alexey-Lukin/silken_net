# SPDX-License-Identifier: AGPL-3.0-or-later
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
    i.define_singleton_method(:to_key) { [ 1 ] }
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

  # ⚠️ Не «покриття заради покриття»: гілки провайдерів чекають на дротування
  # OmniAuth ([`ARCH.69`]), тобто це міна на запобіжнику, а не мертвий код —
  # видаляти не можна, а непокритою вона тягне групову підлогу `Views` вниз.
  # Приклад заразом фіксує, що іконки РІЗНІ: спільна мапа зі збігом значень
  # зробила б провайдерів невідрізнюваними на екрані.
  describe "provider icons" do
    it "дає кожному відомому провайдеру власну іконку" do
      known = %w[google_oauth2 facebook linkedin twitter]
      rendered = render_component(
        user: user,
        identities: known.map { |p| mock_identity(provider: p, uid: "uid-#{p}") }
      )

      icons = %w[🔵 🟦 🔷 🐦]
      icons.each { |icon| expect(rendered).to include(icon) }
      expect(icons.uniq.size).to eq(known.size)
    end

    it "невідомий провайдер дістає запасну іконку" do
      rendered = render_component(user: user, identities: [ mock_identity(provider: "mastodon") ])
      expect(rendered).to include("🔗")
    end
  end

  describe "MFA section" do
    it "renders the Two-Factor Authentication heading" do
      expect(html).to include("Two-Factor Authentication")
    end

    it "shows the under-construction caveat instead of a working control" do
      expect(html).to include("Under construction")
    end

    # [S6.21] Toggle без login-challenge = security-theatre; гейт проти його
    # повернення ДО повного TOTP-контуру (verify-on-login).
    it "does not render an MFA enable/disable toggle" do
      expect(html).not_to include("Enable MFA")
      expect(html).not_to include("Disable MFA")

      user_with_mfa = mock_user(mfa_enabled: true)
      html_enabled = render_component(user: user_with_mfa, identities: identities)
      expect(html_enabled).not_to include("Disable MFA")
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
    let(:html) { render_component(user: user, identities: [ identity ]) }

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
      html = render_component(user: user, identities: [ identity ])
      expect(html).to include("Lock")
    end

    it "renders Unlock button for a locked identity" do
      identity = mock_identity(locked: true)
      html = render_component(user: user, identities: [ identity ])
      expect(html).to include("Unlock")
    end
  end

  describe "available providers" do
    # [ARCH.69] Interim-stub: OmniAuth не задротований — «Link …»-кнопки вели
    # на /auth/:provider = 404. Гейт проти повернення 404-лінків до дротування.
    it "renders no provider-link buttons while OmniAuth is unwired" do
      identity = mock_identity(provider: "google_oauth2")
      html = render_component(user: user, identities: [ identity ])
      expect(html).not_to include("Available Providers")
      expect(html).not_to include("/auth/facebook")
      expect(html).not_to include("Link Facebook")
    end
  end

  describe "unlink button" do
    context "when user has password and single identity" do
      it "renders the Unlink button form" do
        user_with_pwd = mock_user(password_digest: "hashed_secret")
        identity = mock_identity(provider: "google_oauth2")
        html = render_component(user: user_with_pwd, identities: [ identity ])
        expect(html).to include("Unlink")
        expect(html).to include("delete")
      end
    end

    context "when user has no password and only one active identity" do
      it "renders disabled Unlink span" do
        user_no_pwd = mock_user(password_digest: nil)
        identity = mock_identity(provider: "google_oauth2", active: true)
        html = render_component(user: user_no_pwd, identities: [ identity ])
        expect(html).to include("cursor-not-allowed")
      end
    end
  end

  describe "provider_icon else branch" do
    it "renders generic link icon for unknown provider" do
      identity = mock_identity(provider: "github")
      html = render_component(user: user, identities: [ identity ])
      expect(html).to include("🔗")
    end
  end
end
