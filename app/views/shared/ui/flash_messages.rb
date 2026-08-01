# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Views
  module Shared
    module UI
      # [SEC.25] Поверхня, якої в застосунку не було: `flash` ставився в 43 сайтах
      # (перерахунок 2026-08-01; «42» був недоліком запиту — греп за цілим виразом
      # не бачив форм, де kwarg стоїть на власному рядку) і не читався НІДЕ —
      # ані `DashboardLayout`, ані `AuthLayout` його не рендерили,
      # а kwarg'и трьох auth-компонентів заповнюються лише прямим рендером, тобто
      # після `redirect_to` не заповнюються ніким.
      #
      # 🔴 Обидва live-regions присутні в DOM ЗАВЖДИ, навіть порожні — це не стиль, а
      # умова роботи скрінрідера: регіон, вставлений у DOM РАЗОМ зі своїм вмістом, AT
      # не оголошує (вона слухає зміни всередині вже відомого їй регіону). Тому тут
      # рендеряться дві порожні коробки, а текст з'являється всередині них.
      #
      # ⚠️ **Точна межа цієї користі, бо перша редакція цього абзацу обіцяла більше,
      # ніж правда.** Порожня коробка рятує лише там, де вузол регіону ПЕРЕЖИВАЄ
      # оновлення — тобто на morph-візиті (редирект на ту саму адресу). На звичайній
      # навігації `PageRenderer` робить `document.body.replaceWith(newElement)`, тож
      # регіон приходить НОВИМ вузлом із текстом уже всередині, і для `role="status"`
      # оголошення не гарантоване. Рятує там лише спеціальна обробка `role="alert"`
      # (AT озвучує його й у початковій розмітці) — тобто ВІДМОВИ чутно завжди, а
      # ПІДТВЕРДЖЕННЯ успіху для незрячого користувача на більшості шляхів мовчить.
      # Конструкція від цього не стає марною (вона ніде не гірша за альтернативу), але
      # закрити цю вісь до кінця може лише перенесення тексту в сам `role="alert"`
      # або клієнтська вставка після завантаження → `00_07` SEC.25.
      #
      # 🔴 Ролі різні й не взаємозамінні: `alert` = assertive (перебиває мовлення) для
      # відмов, `status` = polite для підтверджень. APG прямо вимагає вживати assertive
      # ощадливо — «успішно збережено» не має права перебивати те, що людина читає.
      #
      # ⚠️ Свідомо БЕЗ таймера й без кнопки закриття. Це не спрощення: WCAG 2.2.1
      # («Timing Adjustable», рівень A) — критерій про ЧАСОВІ ЛІМІТИ, і поки ліміту
      # немає, вимога «дай вимкнути/подовжити» не виникає взагалі. Auto-dismiss тут
      # створив би зобов'язання, яких зараз просто не існує, а на мобільному
      # (`hover: none`) механізму паузи фізично нема — тобто пауза захищала б лише
      # тих, хто і так за столом. Повідомлення живе до наступної навігації — так само,
      # як уже роблять три auth-компоненти.
      #
      # ⚠️ Стеля, названа чесно: на сторінках, що приймають `broadcast_refresh`
      # (`clusters/show` · `alerts/index` · `telemetry/live_stream`), morph зітре це
      # повідомлення наступним refresh'ем — вузла немає у свіжій відповіді, а хука на
      # видалення вузла без пари Turbo назовні не дає. Там канал підтвердження —
      # СТАН (як `Alerts::Row` уже робить), не повідомлення → `00_07` SEC.25 Ф0.
      class FlashMessages < ApplicationComponent
        # ⚠️ Дві категорії — СТАН, а не присуд: розширення до чотирьох
        # (`success` · `error` · `pending` · `security`) ⚖️ ратифіковано 2026-08-01,
        # разом із мапінгом у ці ж два регіони — `error`+`security` → assertive,
        # `success`+`pending` → polite. Тут доти стояло «окреме рішення з власним
        # доказом», тобто рішення ще нема — воно вже є; чекає лише міграції сайтів
        # (атомарної: після перейменування невідома категорія дропається мовчки).
        # Стан → `00_07` SEC.25 Ф3.
        KINDS = {
          "alert" => {
            role: "alert",
            live: "assertive",
            tone: "border-status-danger bg-status-danger text-status-danger-text"
          },
          "notice" => {
            role: "status",
            live: "polite",
            tone: "border-gaia-border bg-gaia-surface-sunken text-gaia-primary"
          }
        }.freeze

        # @param messages [Hash] `{"notice" => "…", "alert" => "…"}` — читає їх
        #   КОНТРОЛЕР (`render_dashboard`/`render_auth_page`) і передає сюди явно.
        #   Компонент навмисно НЕ звертається до `helpers.flash`: поза request-
        #   контекстом (компонентні спеки рендерять через `ApplicationController
        #   .renderer`, Turbo-броадкасти — взагалі без сесії) `helpers` дорівнює nil,
        #   тож читання амбієнтного стану зробило б компонент нерендерабельним там,
        #   де решта дерева рендериться нормально.
        def initialize(messages: {})
          @messages = normalize(messages)
        end

        def view_template
          div(class: "fixed inset-x-0 top-16 md:top-24 z-40 flex flex-col items-center gap-2 px-4 pointer-events-none") do
            KINDS.each_key { |kind| render_region(kind) }
          end
        end

        private

        # Порожній регіон теж рендериться — див. шапку.
        def render_region(kind)
          config = KINDS.fetch(kind)

          div(
            id: "flash_#{kind}",
            role: config[:role],
            aria_live: config[:live],
            aria_atomic: "true",
            class: "w-full max-w-xl"
          ) do
            text = @messages[kind]
            next if text.blank?

            div(class: tokens(
              "p-3 border text-tiny uppercase tracking-widest text-center pointer-events-auto",
              config[:tone]
            )) { text }
          end
        end

        # `flash` приїжджає з `FlashHash` або звичайного Hash; ключі — рядки або
        # символи залежно від того, хто його ставив. Зводимо до рядків і лишаємо
        # тільки відомі категорії: невідомий ключ мовчки НЕ рендериться, бо для
        # нього немає ані ролі, ані тону — а вигадати їх означало б показати
        # повідомлення без семантики.
        def normalize(messages)
          return {} if messages.blank?

          messages.to_h.each_with_object({}) do |(kind, text), acc|
            key = kind.to_s
            acc[key] = text.to_s if KINDS.key?(key) && text.present?
          end
        end
      end
    end
  end
end
