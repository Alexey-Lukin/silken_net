# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sessions::New do
  # The component is i18n-aware. Existing assertions target the English copy,
  # so we render under :en. The `default locale (uk)` describe-block below
  # covers the Ukrainian fallback path explicitly.
  around { |ex| I18n.with_locale(:en) { ex.run } }

  let(:html) { render_component }

  describe "portal header" do
    it "renders Citadel heading" do
      expect(html).to include("Citadel")
    end

    it "renders Establishing Neural Link subtitle" do
      expect(html).to include("Establishing Neural Link")
    end
  end

  describe "form fields" do
    it "renders email input field" do
      expect(html).to include('type="email"')
    end

    it "renders Identity label for email" do
      expect(html).to include("Identity (Email)")
    end

    it "renders password input field" do
      expect(html).to include('type="password"')
    end

    it "renders Access Code label for password" do
      expect(html).to include("Access Code (Password)")
    end

    # 🔴 Наявні приклади вище пінять ТЕКСТ мітки й нічого не кажуть про звʼязок
    # із полем — саме тому голий `<label>` без `for` жив тут непоміченим: мітка
    # рендерилась, приклади були зелені, а скрінрідер поля не називав (WCAG 1.3.1).
    # Пін парсить розмітку, а не шукає рядок: перейменування атрибута чи ключа
    # локалі його не обійде.
    # ⚠️ Предикат — зі СПІЛЬНОГО дому (`spec/support/label_association.rb`), не
    # інлайн: локальна копія знає лише ЯВНУ асоціацію (`for`⟷`id`) і оголосила б
    # сиротою законну ВКЛАДЕНУ мітку. Дім має обидві гілки й власного носія на
    # GREEN-половину; інлайн-копія — це друга реалізація без нього.
    it "associates every label with a real form control" do
      doc = Nokogiri::HTML5.fragment(html)

      expect(doc.css("label")).not_to be_empty, "no labels rendered — the pin would be vacuous"
      expect(LabelAssociation.orphan_labels(doc).map { |l| l.text.strip }).to be_empty
    end

    it "renders AUTHENTICATE submit button" do
      expect(html).to include("AUTHENTICATE")
    end
  end

  describe "forgot password link" do
    it "renders Forgot Access Code link" do
      expect(html).to include("Forgot Access Code?")
    end
  end

  # [SEC.25] Помилка ПОТОЧНОГО сабміту (401/429) — інше дієслово, ніж `FlashMessages`.
  # Приклад про notice-варіант знято разом із kwargом: нуль викликачів у дереві,
  # тобто гілку тримала лише ця спека.
  describe "flash messages" do
    it "renders alert message when flash_alert is present" do
      html = render_component(flash_alert: "Invalid credentials")
      expect(html).to include("Invalid credentials")
      expect(html).to include('role="alert"')
    end

    it "does not render alert div when flash_alert is nil" do
      expect(html).not_to include('role="alert"')
    end
  end

  # [UI.17] Доти тут стояв приклад «renders AES-256 Enabled text», тобто сюїта
  # ВИМАГАЛА безпекову атестацію на публічній сторінці входу, якої ніщо не
  # вимірює. Пін інвертовано, а не знято: така печатка виглядає прикрасою, тож
  # без піна ВІДСУТНОСТІ вона вертається першим редизайном (прецедент —
  # знятий `matrix_rain`, чиїм носієм теж став пін відсутності).
  describe "security footer (знято — атестація без джерела)" do
    it "не стверджує жодної безпекової властивості" do
      expect(html).not_to include("AES-256")
      expect(html).not_to include("Integrity")
    end
  end

  describe "default locale (uk)" do
    it "falls back to Ukrainian copy when no locale override is active" do
      I18n.with_locale(:uk) do
        ua_html = render_component
        expect(ua_html).to include("Цитадель")
        expect(ua_html).to include("АВТЕНТИФІКУВАТИ")
        expect(ua_html).to include("Забули код доступу?")
      end
    end
  end
end
