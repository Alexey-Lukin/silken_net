# frozen_string_literal: true

module Views
  module Shared
    module UI
      # Top-bar dropdown that lets the visitor switch between the available
      # interface languages. Submits a POST to `LocalesController#update`,
      # which writes a permanent cookie and bounces back to the referer.
      #
      # ── Architecture ────────────────────────────────────────────────────
      # Built on the **HTML Popover API** (Baseline 2024 — Chromium 114+,
      # Safari 17+, Firefox 125+). The browser handles outside-click close,
      # Escape close, focus-restore-to-trigger, and stacks the popover on
      # the top-layer above everything else — without a single line of JS.
      #
      # Progressive enhancement: each option is a real Rails `button_to`
      # form, so language switching keeps working when JS is disabled or
      # the popover API isn't supported (the `<button popovertarget>`
      # gracefully degrades to a non-interactive button — the layout still
      # renders, the form below it still posts).
      class LocaleSwitcher < ApplicationComponent
        POPOVER_ID = "locale-switcher-popover"

        # @param current_locale [Symbol] the active locale (defaults to I18n.locale)
        def initialize(current_locale: nil)
          @current_locale = (current_locale || I18n.locale).to_sym
        end

        def view_template
          # Wrapper is `inline-block` + `relative` so the popover (which is
          # absolutely positioned via the top-layer) anchors near the trigger.
          div(class: "relative inline-block") do
            render_trigger
            render_popover
          end
        end

        private

        def render_trigger
          button(
            type: "button",
            popovertarget: POPOVER_ID,
            aria_label: I18n.t("locale.switcher_label", default: "Language"),
            class: tokens(
              "inline-flex items-center gap-2 px-2 py-1.5",
              "border border-gaia-border text-gaia-text-muted",
              "hover:text-gaia-primary hover:border-gaia-primary",
              "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary",
              "transition-colors duration-200"
            )
          ) do
            span(class: "text-tiny font-mono uppercase tracking-widest", aria_hidden: "true") do
              short_label(@current_locale)
            end
            span(class: "sr-only") do
              I18n.t("locale.available.#{@current_locale}", default: @current_locale.to_s)
            end
            chevron_icon
          end
        end

        def render_popover
          # `popover="auto"` (the default) gives light-dismiss for free:
          # outside click and Escape both close the popover natively.
          ul(
            id: POPOVER_ID,
            popover: "auto",
            role: "menu",
            class: tokens(
              # Reset UA popover defaults (margin, border, padding) and
              # re-anchor next to the trigger via inset.
              "m-0 p-1 border border-gaia-border bg-gaia-surface-elevated shadow-lg",
              "min-w-[10rem] origin-top-right"
            )
          ) do
            I18n.available_locales.each do |locale|
              li(role: "none") { render_option(locale) }
            end
          end
        end

        def render_option(locale)
          active = locale == @current_locale
          button_attrs = {
            type: "submit",
            role: "menuitem",
            disabled: active,
            class: tokens(
              "w-full text-left px-3 py-2 text-tiny font-mono uppercase tracking-widest",
              "transition-colors duration-150",
              "focus-visible:outline-none focus-visible:bg-gaia-surface-sunken",
              "text-gaia-text hover:bg-gaia-surface-sunken hover:text-gaia-primary": !active,
              "text-gaia-primary bg-gaia-surface-sunken cursor-default": active
            )
          }
          # String key for the hyphenated ARIA attribute — symbol
          # `aria_current:` would render as `aria_current="true"` (with
          # underscore) when passed through the Rails form builder, breaking
          # screen-reader detection of the active option.
          button_attrs["aria-current"] = "true" if active

          form_with(
            url: api_v1_locale_path,
            method: :post,
            data: { turbo_frame: "_top" },
            class: "block"
          ) do |f|
            f.hidden_field(:locale, value: locale.to_s)
            f.button(button_attrs) do
              "#{short_label(locale)} · #{I18n.t("locale.available.#{locale}", default: locale.to_s)}"
            end
          end
        end

        def short_label(locale)
          { uk: "UA", en: "EN" }[locale.to_sym] || locale.to_s.upcase
        end

        def chevron_icon
          svg(
            xmlns: "http://www.w3.org/2000/svg",
            class: "h-3 w-3",
            fill: "none",
            viewBox: "0 0 24 24",
            stroke: "currentColor",
            stroke_width: "2",
            aria_hidden: "true"
          ) do |s|
            s.path(stroke_linecap: "round", stroke_linejoin: "round", d: "M19 9l-7 7-7-7")
          end
        end
      end
    end
  end
end
