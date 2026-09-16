# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Views
  module Shared
    module UI
      # Кістки плейсхолдера — і НІЧОГО, крім них. Коробку (рамка · фон · відступ)
      # дає ВЛАСНИК вмісту через свою константу `PANEL`, а висоту — виклик через
      # `lines:`, бо лише він знає вміст, замість якого стоїть.
      #
      # 🔴 Доти скелетон малював власну картку `p-10 border bg-gaia-surface`, і вона
      # не збігалась ні з ОДНИМ вмістом: виміряно Δh +52 (баланс) · +171 (метадані
      # гаманця) · −58 (хроніка — картка В картці власника), фон `surface` там, де
      # вміст `sunken`. Носій збігу — `spec/features/skeleton_box_spec.rb`.
      class Skeleton < ApplicationComponent
        # Один словник кістки на весь сайт: ним фарбують і locale-вільні стаби
        # броадкастів, яким сам компонент недоступний. `max-w-full` несучий — кістка
        # фіксованої ширини (`w-64`) інакше виходить за вузьку колонку.
        BONE = "rounded bg-gaia-border animate-pulse max-w-full"

        # Мітка · сума героя · рядок величин · підпис — `Wallets::BalanceDisplay`.
        BALANCE = [
          %w[h-4 w-32],
          %w[h-18 w-64],
          %w[h-4 w-3/4],
          %w[h-4 w-1/2]
        ].freeze

        # `decorative: true` — для broadcast-стабів класу 2 (`04_04 §8.1а`): без
        # `t()`, тож payload побайтово однаковий у кожній локалі; про очікування
        # асистивним технологіям каже сам фрейм (`aria-busy`, ставить Turbo).
        def initialize(variant: nil, lines: 3, decorative: false, **attrs)
          @variant = variant&.to_sym
          @lines = lines
          @decorative = decorative
          @extra_class = attrs[:class]
        end

        def view_template
          div(class: tokens("space-y-4", @extra_class), **a11y_attrs) do
            bones.each { |height, width| div(class: tokens(BONE, height, width)) }
          end
        end

        private

        def a11y_attrs
          return { aria_hidden: "true" } if @decorative

          { role: "status", aria_label: t("ui.skeleton.loading") }
        end

        # Перший рядок вужчий — заголовок; далі чергуються довгий і короткий, як у
        # парі «мітка → значення» чи рядку стрічки.
        def bones
          return BALANCE if @variant == :balance

          Array.new(@lines) { |i| [ "h-4", i.zero? ? "w-1/3" : (i.odd? ? "w-full" : "w-2/3") ] }
        end
      end
    end
  end
end
