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
            class: "flex justify-between items-center mt-6 font-mono text-[9px] uppercase"
          ) do
            if @pagy.prev
              a(
                href: @url_helper.call(page: @pagy.prev),
                aria_label: "Go to previous page",
                class: "px-4 py-2 border border-gray-300 dark:border-emerald-900 text-gray-500 dark:text-emerald-800 " \
                       "hover:border-gaia-primary hover:text-gaia-primary " \
                       "focus:outline-none focus:ring-2 focus:ring-gaia-primary " \
                       "transition-all tracking-widest"
              ) { "← Previous" }
            else
              div
            end

            div(class: "text-gray-400 dark:text-emerald-900", aria_current: "page") { "Page #{@pagy.page} / #{@pagy.last}" }

            if @pagy.next
              a(
                href: @url_helper.call(page: @pagy.next),
                aria_label: "Go to next page",
                class: "px-4 py-2 border border-gray-300 dark:border-emerald-900 text-gray-500 dark:text-emerald-800 " \
                       "hover:border-gaia-primary hover:text-gaia-primary " \
                       "focus:outline-none focus:ring-2 focus:ring-gaia-primary " \
                       "transition-all tracking-widest"
              ) { "Next →" }
            else
              div
            end
          end
        end
      end
    end
  end
end
