# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe AccountSecurity::Show do
  # [TEST.12] Реальні незбережені записи, а не `OpenStruct`. Мок тут вигадував
  # `Identity#active?` — предиката, якого на моделі НЕМА (`active` існує лише
  # скоупом), — і саме тому ховав 500 на сторінці безпеки для кожного власника
  # без пароля. Заразом він оголошував `mfa_enabled`/`recovery_codes_remaining`,
  # яких компонент не читає взагалі (`@user` дає лише `password_digest`).
  # `id` потрібен роут-хелперам кнопок lock/unlink, тож `build_stubbed`.
  def mock_user(password_digest: nil)
    User.new(password_digest: password_digest)
  end

  def mock_identity(provider: "google_oauth2", uid: "1234567890abc", primary: false, locked: false)
    build_stubbed(:identity, provider: provider, uid: uid, primary: primary,
                             locked_at: locked ? 1.hour.ago : nil)
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

    # ✅ [S6.21] Toggle ПОВЕРНУВСЯ разом із verify-on-login — гейт проти нього
    # відпрацював свій контракт і знятий. Пара нижче — обидва боки розвилки,
    # інакше «кнопка є» не відрізнити від «обидві кнопки завжди» (BP 21).
    it "offers the setup flow to a user without MFA — and no disable form" do
      expect(html).to include("Enable MFA")
      expect(html).to include('action="/account_security/mfa_setup"')
      expect(html).not_to include("Disable MFA")
    end

    it "offers step-up disable to an MFA-enabled user — and no enable button" do
      enabled = User.new(password_digest: "x", otp_required_for_login: true,
                         recovery_codes: %w[a b c].to_json)
      html_enabled = render_component(user: enabled, identities: identities)

      expect(html_enabled).to include("Disable MFA")
      expect(html_enabled).to include('name="current_password"')
      expect(html_enabled).not_to include("Enable MFA")
    end

    # Дзеркало контролера: OAuth-only власник не має спільного секрета для
    # step-up, тож поле пароля в disable-формі для нього НЕ рендериться.
    it "omits the step-up field for an OAuth-only MFA user" do
      oauth_only = User.new(password_digest: nil, otp_required_for_login: true,
                            recovery_codes: %w[a].to_json)
      html_enabled = render_component(user: oauth_only, identities: identities)

      expect(html_enabled).to include("Disable MFA")
      expect(html_enabled).not_to include('name="current_password"')
    end
  end

  describe "password form" do
    # 🔴 [UI.3] Сусідні приклади пінять ІМЕНА полів і текст міток — і саме тому голі
    # `<label>` без `for` жили тут непоміченими: усе рендерилось, приклади були зелені,
    # а скрінрідер поля не називав (WCAG 1.3.1, сильніше за 3.3.1). Пін парсить
    # розмітку, а не шукає рядок, тож перейменування ключа локалі його не обійде.
    it "associates every label with a real form control" do
      doc = Nokogiri::HTML5.fragment(html)

      expect(doc.css("label")).not_to be_empty, "no labels rendered — the pin would be vacuous"
      expect(LabelAssociation.orphan_labels(doc).map { |l| l.text.strip }).to be_empty
    end

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
      # [I18N.1] Канонічне написання, не `.titleize`: той давав «Google Oauth2» —
      # тобто цей пін цементував дефект показу як правильну поведінку.
      expect(html).to include("Google")
      expect(html).not_to include("Google Oauth2")
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
        identity = mock_identity(provider: "google_oauth2")
        html = render_component(user: user_no_pwd, identities: [ identity ])
        expect(html).to include("cursor-not-allowed")
      end
    end

    # [TEST.12] Саме цей шлях і падав: без пароля обчислення `can_unlink` доходить
    # до правої половини `||`, тобто до предиката на КОЖНІЙ ідентичності. Доти
    # фікстура вигадувала `active?`, тож приклад був зелений на методі, якого
    # модель не має. На реальному записі приклад червоніє без фікса.
    context "when user has no password but two unlocked identities" do
      it "renders an active Unlink form for each" do
        html = render_component(
          user: mock_user(password_digest: nil),
          identities: [ mock_identity(provider: "google_oauth2", uid: "uid-a"),
                        mock_identity(provider: "facebook", uid: "uid-b") ]
        )
        expect(html).not_to include("cursor-not-allowed")
        expect(html).to include("Unlink")
      end
    end

    # Заблокована ідентичність не рахується «активною» — з однією живою й однією
    # заблокованою відв'язати не можна, інакше власник лишиться без жодного входу.
    context "when the second identity is locked" do
      it "keeps Unlink disabled" do
        html = render_component(
          user: mock_user(password_digest: nil),
          identities: [ mock_identity(provider: "google_oauth2", uid: "uid-a"),
                        mock_identity(provider: "facebook", uid: "uid-b", locked: true) ]
        )
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
