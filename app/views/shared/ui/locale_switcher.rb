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
        # @param current_locale [Symbol] the active locale (defaults to I18n.locale)
        def initialize(current_locale: nil)
          @current_locale = (current_locale || I18n.locale).to_sym
        end

        def view_template
          form_with(
            url: api_v1_locale_path,
            method: :post,
            data: { turbo_frame: "_top" },
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
            I18n.t("locale.switcher_label", default: "Language"),
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
              "appearance-none pr-7 pl-2 py-1 cursor-pointer",
              "border border-gaia-border bg-gaia-surface text-gaia-text",
              "text-tiny font-mono uppercase tracking-widest",
              "hover:text-gaia-primary hover:border-gaia-primary",
              "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary",
              "transition-colors duration-200",
              # Custom chevron via background-image so we can drop UA arrow
              # styling without losing the visual cue.
              "bg-[length:0.6rem] bg-[right_0.5rem_center] bg-no-repeat",
              "bg-[url('data:image/svg+xml;utf8,<svg xmlns=%22http://www.w3.org/2000/svg%22 viewBox=%220 0 24 24%22 fill=%22none%22 stroke=%22currentColor%22 stroke-width=%222%22><path stroke-linecap=%22round%22 stroke-linejoin=%22round%22 d=%22M19 9l-7 7-7-7%22/></svg>')]"
            ),
            aria: { label: I18n.t("locale.switcher_label", default: "Language") },
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
                "hover:text-gaia-primary hover:border-gaia-primary"
              )
            ) { I18n.t("locale.apply", default: "Apply") }
          end
        end

        def option_label(locale)
          short = { uk: "UA", en: "EN" }[locale.to_sym] || locale.to_s.upcase
          long  = I18n.t("locale.available.#{locale}", default: locale.to_s)
          "#{short} · #{long}"
        end
      end
    end
  end
end
