# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Errors::NoOrganization do
  describe "rendering" do
    let(:html) { render_component }

    it "renders the page heading" do
      expect(html).to include("Quarantine")
    end

    it "renders the auth-page subtitle" do
      expect(html).to include("No Organization Assigned")
    end

    it "renders an explanatory message about the Forest Matrix" do
      expect(html).to include("Forest Matrix")
    end

    it "instructs the user to contact an administrator" do
      expect(html).to include("Contact your administrator")
    end

    it "renders a sign-out form" do
      expect(html).to include("Sign Out")
      expect(html).to include('action="/logout"')
      expect(html).to include('name="_method" value="delete"')
    end

    it "wraps content in main with role=main" do
      expect(html).to include('role="main"')
    end
  end

  # [UI.6] Карантин — перший екран платформеного адміністратора (за seeds обидва
  # super_admin без організації), тож питання «чи є звідси вихід» роле-залежне.
  describe "роле-залежний вихід" do
    it "дає super_admin лінк на реєстр кланів" do
      html = render_component(current_user: build_stubbed(:user, :super_admin))

      # Повний шлях, не префікс: пін на початок рядка пропустив би будь-яку
      # сусідню адресу, що з нього починається.
      expect(html).to include(%(href="#{Rails.application.routes.url_helpers.organizations_path}"))
      expect(html).to include("Choose an organization")
    end

    it "каже super_admin про КОНТЕКСТ, а не про членство" do
      html = render_component(current_user: build_stubbed(:user, :super_admin))

      expect(html).to include("Choose the context you want to act in")
      expect(html).not_to include("Contact your administrator")
    end

    it "не пропонує реєстр звичайному користувачеві — там 403" do
      html = render_component(current_user: build_stubbed(:user))

      expect(html).not_to include(%(href="#{Rails.application.routes.url_helpers.organizations_path}"))
      expect(html).to include("Contact your administrator")
    end

    it "без актора виходу не показує (fail-closed)" do
      expect(render_component).not_to include("Choose an organization")
    end
  end

  describe "accessibility" do
    let(:html) { render_component }

    it "marks the decorative diamond logo with aria-hidden" do
      expect(html).to include('aria-hidden="true"')
    end

    it "labels the sign-out button for screen readers" do
      expect(html).to include('aria-label="Sign out"')
    end

    it "applies focus-visible ring on the sign-out button" do
      expect(html).to include("focus-visible:ring-2")
      expect(html).to include("focus-visible:ring-gaia-primary")
    end
  end

  describe "design system compliance" do
    let(:html) { render_component }

    it "uses the custom text scale (text-tiny / text-compact)" do
      expect(html).to include("text-tiny")
      expect(html).to include("text-compact")
    end

    it "uses semantic status-danger-accent token for the danger LED" do
      # NoOrganization сигналізує denied/quarantined-стан — позначаємо семантичним
      # status-danger-accent (docs/04_04 §3.2).
      # ⚠️ Тут доти стояло «решта auth-сторінок використовує raw emerald-палітру за §3.5
      # (виняток для page-components)» — ТРЕТЯ копія дозволу, скасованого 2026-08-07.
      expect(html).to include("border-status-danger-accent")
      expect(html).to include("bg-status-danger-accent")
    end

    # 🔴 Цей приклад звався «matches the Sessions::New / Passwords::Forgot card chrome» і
    # пінив `border-emerald-900` + `bg-black/80` — тобто стверджував ПАРНІСТЬ із сусідом,
    # який уже мігрував на `border-gaia-border` + `bg-gaia-surface/80`. Заява про ЧУЖИЙ
    # файл не має чим упасти, коли той файл змінюють: жоден гейт не звіряє ім'я прикладу
    # з його предметом, тож спека роками цементувала розходження під написом «збігається».
    # Ім'я тепер називає те, що приклад справді перевіряє.
    it "carries the token card chrome (glass preserved, surface theme-aware)" do
      expect(html).to include("border-gaia-border")
      expect(html).to include("bg-gaia-surface/80")
      expect(html).to include("backdrop-blur-xl")
    end
  end

  # 🔴 [UI.3] Ця сторінка — ПЕРШИЙ екран платформеного адміністратора (обидва super_admin
  # у сідах без організації), і її ЄДИНА дія — вихід. Виміряно композитом 2026-08-15:
  # заголовок `text-white` давав **1.04:1** у світлій, кнопка виходу `text-emerald-900` —
  # **1.33:1** світла / **2.17:1** темна, тобто була невидима в ОБОХ темах.
  #
  # ⚠️ Корінь дефекту не в кольорах, а в тому, що `main` не мав ЖОДНОЇ поверхні — текст
  # шапки висів на успадкованому тлі. Тому liveness-пін нижче стереже саме поверхню:
  # без неї токен-текст лишається без відомої пари, і будь-яке число про нього — здогад.
  #
  # 🔒 Стеля: судиться ТЕКСТ. Watermark-сітка (`bg-[radial-gradient(#10b981…)]`) лишається
  # сирою свідомо — `aria-hidden`-декорація. ✅ CTA переведено на `text-gaia-primary-strong`
  # (2026-08-18): доти `text-gaia-primary` давав тут **2.52:1** у світлій — тобто ✅ від
  # 08-15 підняв його з 1.33, але НЕ до бару, і цей коментар чесно чекав на парний
  # токен для всієї когорти. Токен заведено (`04_04 §3.1`), сайт закрито: 5.44 світла,
  # 7.69 темна (без змін). ⚠️ Число когорти звідси знято свідомо — воно дрейфує;
  # решта міграції належить [`UI.1`](../../../../docs/00_07_Action_Plan_Tracker.md).
  describe "token discipline (contrast)" do
    let(:html) { render_component }

    it "рендерить текст на токенах і має ВЛАСНУ поверхню" do
      expect(html).to include("bg-gaia-surface-base"), "корінь без поверхні — пара fg/bg невідома"
      expect(html).to include("text-gaia-text-strong")
      expect(html).to include("text-gaia-text-subtle")

      expect(html).not_to match(/\btext-(?:white|(?:gray|zinc|neutral|slate|stone)-\d+|emerald-\d+)\b/)
    end
  end
end
