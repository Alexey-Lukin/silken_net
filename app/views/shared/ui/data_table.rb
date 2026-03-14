# frozen_string_literal: true

module Views
  module Shared
    module UI
      class DataTable < ApplicationComponent
        def initialize(columns:, empty_message: "No records found.", &block)
          @columns = columns
          @empty_message = empty_message
          @rows_block = block
        end

        def view_template
          div(class: "border border-gray-200 dark:border-emerald-900 bg-white dark:bg-black overflow-x-auto w-full transition-colors duration-300") do
            table(class: "w-full text-left font-mono text-[11px]", role: "table") do
              render_thead
              tbody(class: "divide-y divide-gray-100 dark:divide-emerald-900/30", &@rows_block)
            end
          end
        end

        private

        def render_thead
          thead(class: "bg-gray-50 dark:bg-emerald-950/20 text-gray-500 dark:text-emerald-800 uppercase text-[9px] tracking-widest transition-colors duration-300") do
            tr do
              @columns.each do |col|
                th(scope: "col", class: tokens("p-4", col[:class])) { col[:label] }
              end
            end
          end
        end
      end
    end
  end
end
