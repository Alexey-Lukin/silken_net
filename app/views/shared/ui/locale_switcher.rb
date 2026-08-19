# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Views
  module Shared
    module UI
      # Top-bar language selector built on a native `<select>` + auto-submit
      # form. This is the Rails-canonical pattern: the browser handles
      # positioning, keyboard navigation, focus management and accessibility
      # for free, with zero custom JS.
      #
      # ── Why a native <select> (and not a custom popover)? ───────────────
      # Earlier iterations used the HTML Popover API, which promotes the
      # dropdown to the top layer and detaches it from the normal containing
      # block — so CSS `position: relative` on the wrapper couldn't anchor
      # it next to the trigger, and we had to add a Stimulus controller to
      # re-position via `getBoundingClientRect()`. That works but is fragile
      # (resize/scroll handlers, edge-case z-index conflicts, focus quirks)
      # and adds a JS dependency for a 2-option menu. A native `<select>`
      # is the obvious correct primitive.
      #
      # ── Progressive enhancement ────────────────────────────────────────
      # `onchange="this.form.requestSubmit()"` submits the form the instant
      # the user picks a different option (no separate "Apply" click). When
      # JS is disabled the visible submit button takes over — the form still
      # works end-to-end.
      class LocaleSwitcher < ApplicationComponent
        # [I18N.3] Дволітерний префікс деривується як `code.upcase` для БУДЬ-ЯКОЇ
        # локалі — включно з тією, якої ще немає. Поіменний запис потрібен рівно
        # там, де код мови розходиться з тим, що людина очікує побачити, і такий
        # випадок один: `uk` (ISO 639-1, мова) проти «UA», яку впізнає українець
        # (ISO 3166-1, країна). У `<html lang>` лишається саме `uk` — чому, каже
        # `04_04 §12.2`.
        #
        # 🔴 Тут БІЛЬШЕ НІЧОГО не вписується. Раніше хеш ніс усі чотири локалі,
        # і три з них дослівно дорівнювали власному фолбеку — тобто це був другий
        # реєстр локалей, який на орієнтирі 150+ мов запрошував дописувати кожну
        # нову. Дім списку один: `config.i18n.available_locales`.
        SHORT_CODE_OVERRIDES = { uk: "UA" }.freeze

        # @param current_locale [Symbol] the active locale (defaults to I18n.locale)
        def initialize(current_locale: nil)
          @current_locale = (current_locale || I18n.locale).to_sym
        end

        def view_template
          # 🔴 [UI.11 крок 3] `data: { turbo: "false" }` знято 2026-08-06 — але НЕ
          # «разом із причиною», як планував пункт. Стара причина справді померла
          # (обхід компенсував ЧУЖІ permanent-вузли: спершу сайдбар, потім
          # `#theme-switcher` із локалізованим `aria-label` — обидва зняті), а на
          # її місці ВИМІРЯНО іншу, живу.
          #
          # 🔒 `turbo_action: "advance"` — несуча умова, доведена обома кінцями.
          # Ендпоінт редиректить НА ТОЙ САМИЙ шлях (`redirect_back_or_to`), а Turbo
          # морфить рівно тоді, коли шлях той самий І дія `replace`:
          #   isPageRefresh(v) { … pathname === v.location.pathname && v.action === "replace" }
          # Морф, на відміну від звичайного рендеру, `<body>` не заміняє — тож
          # Stimulus не переграється, а Idiomorph зносить дітей без пари в новій
          # розмітці, тобто полотно Leaflet, збудоване клієнтом. Виміряно
          # браузером: без цього атрибута після перемикання мови `.leaflet-pane`
          # зникає ЦІЛКОМ. `getVisitAction(submitter, formElement)` має пріоритет
          # над дефолтною дією, тож `advance` вимикає морф за побудовою. Ціна
          # названа й прийнята: зайвий запис в історії на кожне перемикання.
          #
          # ⚠️ Носій умови — браузерний приклад у
          # `spec/features/dashboard_browser_smoke_spec.rb`, не цей коментар:
          # знімеш атрибут — приклад червоніє саме на мапі.
          form_with(
            url: locale_path,
            method: :post,
            data: { turbo_action: "advance" },
            class: "inline-flex items-center gap-2"
          ) do |f|
            render_label(f)
            render_select(f)
            render_apply_button
          end
        end

        private

        def render_label(form)
          # Visually-hidden label keeps the control accessible without
          # cluttering the top bar. The current locale's short code (UA/EN)
          # is rendered visually in front of the <select> via the trigger
          # text the browser draws.
          form.label(
            :locale,
            t("locale.switcher_label", default: "Language"),
            class: "sr-only"
          )
        end

        def render_select(form)
          options = I18n.available_locales.map do |locale|
            [ option_label(locale), locale.to_s ]
          end

          form.select(
            :locale,
            options,
            { selected: @current_locale.to_s },
            class: tokens(
              "gaia-select",
              "appearance-none pr-7 pl-2 py-1 cursor-pointer",
              "border border-gaia-border bg-gaia-surface text-gaia-text",
              "text-tiny font-mono uppercase tracking-widest",
              "hover:text-gaia-primary-strong hover:border-gaia-primary",
              "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary-strong",
              "transition-colors duration-200"
            ),
            aria: { label: t("locale.switcher_label", default: "Language") },
            onchange: "this.form.requestSubmit()"
          )
        end

        # Visible only when JS is disabled (the `onchange` auto-submit covers
        # the common path). `noscript` markup wrapping the button keeps the
        # top bar tidy when JS is on.
        def render_apply_button
          noscript do
            button(
              type: "submit",
              class: tokens(
                "px-2 py-1 border border-gaia-border text-gaia-text-muted",
                "text-tiny font-mono uppercase tracking-widest",
                "hover:text-gaia-primary-strong hover:border-gaia-primary"
              )
            ) { t("locale.apply", default: "Apply") }
          end
        end

        def option_label(locale)
          short = SHORT_CODE_OVERRIDES.fetch(locale.to_sym, locale.to_s.upcase)
          long  = t("locale.available.#{locale}", default: locale.to_s)
          "#{short} · #{long}"
        end
      end
    end
  end
end
