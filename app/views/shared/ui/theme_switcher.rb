# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Views
  module Shared
    module UI
      class ThemeSwitcher < ApplicationComponent
        # 🔴 [UI.11 крок 3] `data-turbo-permanent` тут БУЛО й знято 2026-08-06 —
        # це був останній permanent-вузол дерева. Правило, яке він порушував,
        # записане в `04_04 §8`: permanent не ставлять на вузол, усередину якого
        # СЕРВЕР рендерить дані. Тут «дані» — це `aria-label`: Turbo при
        # Drive-візиті пересаджує старий вузол (Bardo), а morph permanent-вузли
        # пропускає взагалі, тож ім'я тумблера застрягало мовою ПЕРШОГО візиту.
        # Дефект був невидимий для зрячого QA (кнопка не має видимого тексту) і
        # коштував сусідові обходу: `LocaleSwitcher` мусив ходити повним
        # перезавантаженням, бо інакше перемикання мови лишало тумблер чужою.
        #
        # Ціна зняття названа чесно: іконку тепер відновлює Stimulus на кожному
        # візиті (`theme#connect` → `applyTheme` → `updateIcon`), тоді як раніше
        # її ніс пересаджений вузол. Сама ТЕМА від цього не блимає — клас `.dark`
        # живе на `<html>`, який Turbo не чіпає (замінюється лише `<body>`), а на
        # повному завантаженні його ставить блокуючий FOUC-скрипт у `<head>`.
        def view_template
          div(id: "theme-switcher", data: { controller: "theme" }) do
            button(
              type: "button",
              aria_label: t("theme.toggle_label"),
              class: "p-2 border border-gaia-border text-gaia-text-muted " \
                     "hover:text-gaia-primary hover:border-gaia-primary " \
                     "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary " \
                     "transition-colors duration-300",
              data: { action: "click->theme#toggle", theme_target: "icon" }
            ) do
              # Default: moon icon (placeholder replaced by Stimulus on connect)
              raw_svg_moon
            end
          end
        end

        private

        def raw_svg_moon
          svg(
            xmlns: "http://www.w3.org/2000/svg",
            class: "h-5 w-5",
            fill: "none",
            viewBox: "0 0 24 24",
            stroke: "currentColor",
            stroke_width: "2"
          ) do |s|
            s.path(
              stroke_linecap: "round",
              stroke_linejoin: "round",
              d: "M20.354 15.354A9 9 0 018.646 3.646 9.005 9.005 0 0012 21a9.005 9.005 0 008.354-5.646z"
            )
          end
        end
      end
    end
  end
end
