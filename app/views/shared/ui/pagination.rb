# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Views
  module Shared
    module UI
      class Pagination < ApplicationComponent
        # @param pagy [Pagy] pagination metadata (must respond to :last, :previous, :next, :page)
        # @param url_helper [#call] lambda that builds page URL, e.g. ->(page:) { path(page: page) }
        # @param sticky_mobile [Boolean] when true the nav becomes sticky-bottom on mobile,
        #   honouring iOS safe-area-inset (CSS class `gaia-pagination-sticky` in application.css).
        # @param compact_mobile [Boolean] when true the indicator switches to a compact
        #   "X / Y" form on narrow viewports so prev/next buttons stay reachable.
        def initialize(pagy:, url_helper:, sticky_mobile: false, compact_mobile: true)
          raise ArgumentError, "pagy must respond to :page" unless pagy.respond_to?(:page)

          @pagy = pagy
          @url_helper = url_helper
          @sticky_mobile = sticky_mobile
          @compact_mobile = compact_mobile
        end

        def view_template
          return if @pagy.last <= 1

          nav(
            aria_label: t("pagination.aria_label"),
            role: "navigation",
            class: tokens(nav_classes, "gaia-pagination-sticky": @sticky_mobile)
          ) do
            render_previous
            render_indicator
            render_next
          end
        end

        private

        def render_previous
          if @pagy.previous
            a(
              href: @url_helper.call(page: @pagy.previous),
              aria_label: t("pagination.previous_aria"),
              class: page_link_classes,
              rel: "prev"
            ) { t("pagination.previous") }
          else
            # Empty placeholder keeps the flex layout symmetrical.
            div(aria_hidden: "true")
          end
        end

        def render_next
          if @pagy.next
            a(
              href: @url_helper.call(page: @pagy.next),
              aria_label: t("pagination.next_aria"),
              class: page_link_classes,
              rel: "next"
            ) { t("pagination.next") }
          else
            div(aria_hidden: "true")
          end
        end

        def render_indicator
          # Two parallel labels: full text on `md+`, compact "1 / 7" on mobile
          # (when `compact_mobile`). Both render so screen readers always get
          # the verbose copy via `sr-only`; sighted users see whatever the
          # active breakpoint reveals.
          div(class: "text-gaia-text-muted", aria_current: "page") do
            full = t("pagination.page_indicator", current: @pagy.page, total: @pagy.last)
            if @compact_mobile
              compact = t("pagination.page_indicator_compact", current: @pagy.page, total: @pagy.last)
              span(class: "sr-only md:not-sr-only md:inline") { full }
              span(class: "md:hidden", aria_hidden: "true") { compact }
            else
              span { full }
            end
          end
        end

        def nav_classes
          "flex justify-between items-center font-mono text-mini uppercase gap-3"
        end

        def page_link_classes
          "px-4 py-2 border border-gaia-border text-gaia-text-muted tracking-widest " \
            "hover:border-gaia-primary hover:text-gaia-primary-strong " \
            "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary " \
            "transition-all duration-200 ease-in-out"
        end
      end
    end
  end
end
