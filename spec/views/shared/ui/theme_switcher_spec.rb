# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Views::Shared::UI::ThemeSwitcher do
  describe "rendered HTML" do
    let(:html) { render_component }

    it "wraps in a div with data-controller=theme" do
      expect(html).to include('data-controller="theme"')
    end

    it "renders a toggle button with click->theme#toggle action" do
      expect(html).to include('data-action="click->theme#toggle"')
    end

    it "renders a button with data-theme-target=icon" do
      expect(html).to include('data-theme-target="icon"')
    end

    it "renders an SVG icon as default content" do
      expect(html).to include("<svg")
      expect(html).to include("</svg>")
    end

    it "keeps a stable id as the hook for browser-level pins" do
      expect(html).to include('id="theme-switcher"')
    end

    # 🔴 [UI.11 крок 3] Атрибут ЗНЯТО, і пін перевернуто разом із ним. Причина не
    # стилістична: Turbo при Drive-візиті ПЕРЕСАДЖУЄ permanent-вузол (Bardo) і
    # викидає свіжу серверну розмітку, а всередині цього вузла стоїть
    # `aria_label: t("theme.toggle_label")` — тобто локалізований рядок. Доки
    # атрибут був на місці, перемикач мов мусив ходити повним перезавантаженням
    # (`data-turbo="false"`), інакше ім'я тумблера застрягало б мовою першого
    # візиту — і зрячий QA цього не побачив би, бо видимого тексту в кнопці немає.
    #
    # ⚠️ Пін на ВІДСУТНІСТЬ, а не на присутність: зворотний рецидив (хтось
    # повертає атрибут «щоб не блимало») знову заморозить ім'я, і мовчки.
    # Поведінкову половину — що ім'я справді їде за мовою сторінки — тримає
    # браузерний приклад у `spec/features/dashboard_browser_smoke_spec.rb`,
    # бо в компонентній спеці Turbo не існує за побудовою.
    it "carries NO data-turbo-permanent — it wraps a localized aria-label" do
      expect(html).not_to include("data-turbo-permanent")
    end
  end

  describe "accessibility" do
    let(:html) { render_component }

    it "includes aria-label for the toggle button" do
      expect(html).to include("aria-label")
      expect(html).to include(I18n.t("theme.toggle_label"))
    end

    it "renders a button element" do
      expect(html).to include("<button")
    end
  end

  describe "styling" do
    let(:html) { render_component }

    it "uses gaia design system border token" do
      expect(html).to include("border-gaia-border")
    end

    it "uses transition-colors for smooth theme switching" do
      expect(html).to include("transition-colors")
    end
  end
end
