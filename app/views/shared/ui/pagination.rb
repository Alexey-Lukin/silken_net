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

          div(class: "flex justify-between items-center mt-6 font-mono text-[9px] uppercase") do
            if @pagy.prev
              a(
                href: @url_helper.call(page: @pagy.prev),
                class: "px-4 py-2 border border-emerald-900 text-emerald-800 hover:border-emerald-600 " \
                       "hover:text-emerald-600 transition-all tracking-widest"
              ) { "← Previous" }
            else
              div
            end

            div(class: "text-emerald-900") { "Page #{@pagy.page} / #{@pagy.last}" }

            if @pagy.next
              a(
                href: @url_helper.call(page: @pagy.next),
                class: "px-4 py-2 border border-emerald-900 text-emerald-800 hover:border-emerald-600 " \
                       "hover:text-emerald-600 transition-all tracking-widest"
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
