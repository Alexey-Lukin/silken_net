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
# 🔴 Тут доти стояло, що raw emerald — «легальний виняток із токен-правила `04_04 §3`,
# бо це domain page-component». Той дозвіл СКАСОВАНО 2026-08-07 (`04_04 §1`/`§3.5`:
# сира поверхня чи сирий текст на доменній сторінці = дефект теми), тобто коментар
# роками оголошував санкціонованим рівно те, що робило цю сторінку невидимою:
# `text-white` на світлому тлі давав **1.04:1**, а `text-emerald-300/80` — **1.37:1**.
# Остання лінія оборони показувала порожній екран тому, хто має світлу ОС.
#
# Текст тепер на токенах. Сирим лишається САМЕ декоративне: ромб-гліф (`TONES`) і
# растрова сітка-watermark — обидва `aria-hidden`, тем-інваріантні за задумом.
# ⚖️ Чи має тон `:info` їхати на `status-info` замість бренд-emerald — питання
# ГУЧНОСТІ, не правдивості, і воно відкрите (`00_07` UI.3): фаза смаку окрема.
module Errors
  class Page < ApplicationComponent
    # Тон = вага помилки, а не смак: 404 не повинен кричати так само, як 500.
    #
    # 🔴 Ромб — це СИГНАЛ (non-text, WCAG 1.4.11 = 3:1), тож усі три тони мусять брати
    # НАСИЧЕНЕ значення, а не пастельний фон бейджа. Виміряно 2026-08-15 композитом на
    # тлі сторінки: `bg-status-warning` (`#fef3c7`) давав **1.07:1** у світлій темі —
    # гліф 403 був фактично невидимий, і саме той тон, що мав би попереджати. Лік — не
    # інший відтінок, а ПАРНИЙ токен `--status-warning-accent` (форма, яку danger має
    # від початку); дім значень і їхнє обґрунтування — `application.css`.
    #
    # `:info` → `--status-info-accent` [UI.1 порція 10]: токен, на який попередня
    # редакція відкладала цей тон («родину закриє …-accent, коли знадобиться комусь
    # іще»), існує з 2026-08-20 — сигнальна хвиля завела його для low-severity, тож
    # умова відкладення настала. ⛔ Заборона на пастельний `status-info` чинна досі:
    # той — ФОН бейджа (`#dbeafe`, 1.17:1 на тлі сторінки), сигнал бере лише
    # насичений парний токен (1.4.11 = 3:1; info-accent міряє ≥5.24 обома темами).
    TONES = {
      danger: "border-status-danger-accent bg-status-danger-accent",
      warning: "border-status-warning-accent bg-status-warning-accent",
      info: "border-status-info-accent bg-status-info-accent"
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
                 "bg-[radial-gradient(var(--gaia-primary)_1px,transparent_1px)] [background-size:20px_20px]",
          aria_hidden: "true"
        )

        div(class: "w-full max-w-md relative z-10 text-center") do
          render_glyph
          h1(class: "text-3xl font-extralight text-gaia-text-strong tracking-[0.3em] uppercase mt-6") { @heading }
          p(class: "text-compact text-gaia-text-muted leading-relaxed mt-4") { @message }
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
