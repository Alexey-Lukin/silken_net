# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe AccountSecurity::Show do
  # [TEST.12] Реальний незбережений запис, а не `OpenStruct`.
  def mock_user(password_digest: nil)
    User.new(password_digest: password_digest)
  end

  def render_component(user:)
    ApplicationController.renderer.render(
      component_class.new(user: user),
      layout: false
    )
  end

  let(:user) { mock_user }
  let(:html) { render_component(user: user) }

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
      html_enabled = render_component(user: enabled)

      expect(html_enabled).to include("Disable MFA")
      expect(html_enabled).to include('name="current_password"')
      expect(html_enabled).not_to include("Enable MFA")
    end

    # Дзеркало контролера: OAuth-only власник не має спільного секрета для
    # step-up, тож поле пароля в disable-формі для нього НЕ рендериться.
    it "omits the step-up field for an OAuth-only MFA user" do
      oauth_only = User.new(password_digest: nil, otp_required_for_login: true,
                            recovery_codes: %w[a].to_json)
      html_enabled = render_component(user: oauth_only)

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
      html = render_component(user: user_with_pwd)
      expect(html).to include('name="current_password"')
    end

    it "shows Set Password button when no password" do
      expect(html).to include("Set Password")
    end

    it "shows Change Password button when password already set" do
      user_with_pwd = mock_user(password_digest: "hashed_secret")
      html = render_component(user: user_with_pwd)
      expect(html).to include("Change Password")
    end
  end

  # [SEC.18] Двері до DSAR-експорту. Механізм жив із 2026-08-20, а посилань на
  # нього в дереві було НУЛЬ — «сервіс відвантажено» ⊥ «субʼєкт може ним
  # скористатись», і на комплаєнс-поверхні це різні твердження.
  describe "DSAR data-export door" do
    # 🔴 Пін цілить в АРГУМЕНТ (href), а не в наявність будь-якого посилання:
    # інакше приклад був би зелений і на кнопці, що веде куди завгодно —
    # рівно той клас, що вже коштував на UI.7 («кнопка є, веде не туди»).
    it "links to the real export route" do
      expect(html).to include(%(href="#{Rails.application.routes.url_helpers.account_security_data_export_path}"))
    end

    # 🔴 Свідок ЛОКАЛІЗАЦІЇ мусить жити в НЕ-базовій локалі: в `en` мітка і
    # її англійське джерело збіглися б, тож приклад був би зелений і з
    # зашитим рядком, тобто про механізм не доводив би нічого.
    it "renders the localized label outside the base locale" do
      localized = I18n.with_locale(:uk) { render_component(user: user) }

      expect(localized).to include("Експортувати мої дані")
      expect(localized).not_to include("Export my data")
    end

    # 🔴 Пін на ФОРМУ керування, і він не косметичний: правило UI.7 («дію рендери
    # через `button_to`/`form_with`») читається як універсальне, тож наступний
    # прохід має природний мотив «полагодити» це посилання у форму — а екшен GET,
    # і POST на нього дав би routing-помилку. Anchor тут ПРАВИЛЬНИЙ, бо нічого
    # не мутує; форма оголосила б мутацію, якої немає.
    # ⚠️ Перша редакція цього прикладу пінила відсутність кнопки СТИРАННЯ через
    # `method="delete"` — рядка, якого Rails не друкує ніколи (`button_to` кладе
    # прихований `_method`), тож приклад був ВАКУУМНИЙ і пережив би появу такої
    # кнопки. Спіймала пакетна мутація, не сюїта: питай не «чи червоніє мій пін»,
    # а «які з N пінів НЕ почервоніли».
    it "offers the export as a GET link, never a mutating form" do
      path = Rails.application.routes.url_helpers.account_security_data_export_path

      expect(html).to include(%(<a href="#{path}"))
      expect(html).not_to include(%(action="#{path}"))
    end
  end

  # [SEC.18] Дзеркальна половина експорту: двері до Art.17 erasure.
  # ⚖️ founder 2026-08-21 — запобіжник step-up на пароль; механізм
  # (`Gdpr::AnonymizeUserService`) жив із нулем викликачів, поки форма присуду
  # була відкрита.
  describe "Art.17 erasure door" do
    let(:erase_path) { Rails.application.routes.url_helpers.account_security_erase_path }
    # ⚠️ Дефолтний `user` цієї спеки — БЕЗ пароля, тож він і є негативним
    # контролем нижче; для позитивних прикладів пароль потрібен явно.
    let(:with_password) { render_component(user: mock_user(password_digest: "argon2-digest")) }

    # 🔴 Пін цілить в АРГУМЕНТ (`action`), не в наявність форми: інакше приклад
    # був би зелений і на формі, що постить куди завгодно — той самий клас, що
    # вже коштував на UI.7.
    it "submits to the real erase route" do
      expect(with_password).to include(%(action="#{erase_path}"))
    end

    # 🔴 Дієслово їде прихованим `_method`, бо браузер не вміє DELETE із форми.
    # Пін саме на нього: `form_with(method: :delete)` без цього рядка означав би
    # POST на маршрут, якого немає, тобто кнопка вела б у routing-помилку.
    it "carries the DELETE verb as Rails encodes it" do
      expect(with_password).to include(%(name="_method" value="delete"))
    end

    # 🔴 Дзеркало гарда контролера, і це НЕ косметика: акт незворотний, тож для
    # акаунта без спільного секрета step-up неможливий, і кнопка вела б у
    # гарантовану відмову. Негативний контроль — дефолтний `user` без пароля.
    # ⚠️ Цей гард має ДРУГОГО свідка, і він точніший за цей приклад: MFA-секція
    # пінить `not_to include('name="current_password"')` для OAuth-only власника,
    # а форма стирання несе поле з тим самим імʼям. Тож зняття гарда червонить
    # ОБИДВА приклади — сусідній не зламався, він спрацював. Записано, щоб
    # наступний читач не шукав колізії там, де є подвійне покриття.
    it "hides the whole section when the account has no password to step up with" do
      expect(html).not_to include(%(action="#{erase_path}"))
      expect(html).not_to include("Erase account")
    end

    # 🔴 Свідок ЛОКАЛІЗАЦІЇ живе в НЕ-базовій локалі: в `en` мітка збіглася б із
    # власним англійським джерелом, і приклад був би зелений навіть із зашитим
    # рядком.
    it "renders the localized label outside the base locale" do
      localized = I18n.with_locale(:uk) do
        render_component(user: mock_user(password_digest: "argon2-digest"))
      end

      expect(localized).to include("Стерти мій акаунт")
      expect(localized).not_to include("Erase my account")
    end
  end
end
