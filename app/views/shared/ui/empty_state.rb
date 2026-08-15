# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Views
  module Shared
    module UI
      class EmptyState < ApplicationComponent
        def initialize(title:, description: nil, icon: "○", colspan: nil)
          @title       = title
          @description = description
          @icon        = icon
          @colspan     = colspan
        end

        def view_template
          if @colspan
            tr do
              td(colspan: @colspan, class: "p-10 text-center") { render_content }
            end
          else
            div(class: "col-span-full p-20 border border-dashed border-gaia-border text-center transition-colors duration-300", role: "status") do
              render_content
            end
          end
        end

        private

        def render_content
          # Прозорість тут ЗАКОННА рівно тому, що вузол оголошений декоративним:
          # `aria_hidden` знімає гліф із дерева доступності, а WCAG 1.4.3 не
          # ставить вимог до чистої декорації. Це і є машинний дискримінатор
          # класу — не «схоже на іконку», а власна семантична декларація.
          p(class: "text-gaia-text-muted text-lg opacity-50", aria_hidden: "true") { @icon }
          p(class: "text-gaia-text-muted font-mono text-xs uppercase tracking-widest") { @title }
          if @description
            # 🔴 [UI.3] Тут доти стояла `opacity-70` — приглушення ПОВЕРХ уже
            # приглушеного токена, і воно давало 3.54:1 у СВІТЛІЙ темі проти
            # порогу 4.5:1 (`text-tiny`), тоді як у темній 6.69:1. Тобто дефект
            # був однотемний: половина глядачів бачила справний екран, і жоден
            # наш прилад цього не судив — токен правильний, пара fg/bg
            # правильна, губить ТРЕТІЙ множник.
            p(class: "text-gaia-text-muted font-mono text-tiny mt-2") { @description }
          end
        end
      end
    end
  end
end
