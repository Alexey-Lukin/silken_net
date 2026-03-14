# frozen_string_literal: true

module Views
  module Shared
    module UI
      class Pagination < ApplicationComponent
        # @param pagy [Pagy] pagination metadata (must respond to :last, :prev, :next, :page)
        # @param url_helper [#call] lambda that builds page URL, e.g. ->(page:) { path(page: page) }
        def initialize(pagy:, url_helper:)
          raise ArgumentError, "pagy must respond to :page" unless pagy.respond_to?(:page)

          @pagy = pagy
          @url_helper = url_helper
        end

        def view_template
          return if @pagy.last <= 1

          nav(
            aria_label: "Pagination",
            role: "navigation",
            class: nav_classes
          ) do
            if @pagy.prev
              a(
                href: @url_helper.call(page: @pagy.prev),
                aria_label: "Go to previous page",
                class: page_link_classes
              ) { "← Previous" }
            else
              div
            end

            div(class: "text-gaia-text-muted", aria_current: "page") { "Page #{@pagy.page} / #{@pagy.last}" }

            if @pagy.next
              a(
                href: @url_helper.call(page: @pagy.next),
                aria_label: "Go to next page",
                class: page_link_classes
              ) { "Next →" }
            else
              div
            end
          end
        end

        private

        def nav_classes
          "flex justify-between items-center font-mono text-mini uppercase"
        end

        def page_link_classes
          "px-4 py-2 border border-gaia-border text-gaia-text-muted tracking-widest " \
            "hover:border-gaia-primary hover:text-gaia-primary " \
            "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary " \
            "transition-all duration-200 ease-in-out"
        end
      end
    end
  end
end
