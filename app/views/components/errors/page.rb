# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [SEC.25] Спільна сторінка помилки для `BaseController`-рендерерів, що мають HTML-гілку
# (`render_not_found` · `render_forbidden_pundit` · `render_internal_server_error`).
#
# 🔴 Компонент СВІДОМО не має жодного власного `t()` — увесь текст приходить параметром.
# Причина не стилістична: `raise_on_missing_translations` робить будь-який відсутній ключ
# винятком, а ці рендерери працюють ЗСЕРЕДИНИ `rescue_from` — виняток там Rails уже не
# переловить, тобто забутий ключ перетворив би сторінку помилки на сиру 500. Нуль власних
# ключів = нуль способів впасти на останньому рубежі.
#
# Лягає в ОБИДВА layout'и без гілок: `AuthLayout` і `DashboardLayout` просто рендерять
# `@content`, а панель центрується власним `min-h-[60vh]` — у дашборді вона займає
# контент-область, в auth-шаблоні майже весь екран.
#
# Стиль: domain page-component (як `Errors::NoOrganization`), тож raw emerald — легальний
# виняток із токен-правила `04_04 §3`.
module Errors
  class Page < ApplicationComponent
    # Тон = вага помилки, а не смак: 404 не повинен кричати так само, як 500.
    TONES = {
      danger: "border-status-danger-accent bg-status-danger-accent",
      warning: "border-status-warning bg-status-warning",
      info: "border-emerald-700 bg-emerald-700"
    }.freeze

    # @param heading [String] заголовок, уже локалізований викликачем
    # @param message [String] людське речення (беремо готові `errors.api.*`)
    # @param tone [Symbol] :danger | :warning | :info
    def initialize(heading:, message:, tone: :danger)
      @heading = heading
      @message = message
      @tone    = TONES.key?(tone) ? tone : :danger
    end

    def view_template
      main(
        class: "min-h-[60vh] flex items-center justify-center p-4 relative overflow-hidden",
        role: "main"
      ) do
        div(
          class: "absolute inset-0 opacity-10 pointer-events-none " \
                 "bg-[radial-gradient(#10b981_1px,transparent_1px)] [background-size:20px_20px]",
          aria_hidden: "true"
        )

        div(class: "w-full max-w-md animate-in zoom-in duration-700 relative z-10 text-center") do
          render_glyph
          h1(class: "text-3xl font-extralight text-white tracking-[0.3em] uppercase mt-6") { @heading }
          p(class: "text-compact text-emerald-300/80 leading-relaxed mt-4") { @message }
        end
      end
    end

    private

    def render_glyph
      div(class: tokens("inline-block h-12 w-12 border rotate-45 relative", TONES[@tone].split.first),
          aria_hidden: "true") do
        div(class: tokens("absolute inset-1 animate-pulse", TONES[@tone].split.last))
      end
    end
  end
end
