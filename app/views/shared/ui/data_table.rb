# frozen_string_literal: true

module Views
  module Shared
    module UI
      class DataTable < ApplicationComponent
        def initialize(columns:, empty_message: "No records found.", **attrs, &block)
          @columns = columns
          @empty_message = empty_message
          @extra_class = attrs[:class]
          @rows_block = block
        end

        def view_template
          div(class: tokens(wrapper_classes, @extra_class)) do
            table(class: table_classes, role: "table") do
              render_thead
              tbody(class: "divide-y divide-gray-100 dark:divide-emerald-900/30", &@rows_block)
            end
          end
        end

        private

        def wrapper_classes
          "border border-gray-200 dark:border-emerald-900 bg-white dark:bg-black overflow-x-auto w-full transition-colors duration-300"
        end

        def table_classes
          "w-full text-left font-mono text-compact"
        end

        def render_thead
          thead(class: thead_classes) do
            tr do
              @columns.each do |col|
                th(scope: "col", class: tokens("p-4", col[:class])) { col[:label] }
              end
            end
          end
        end

        def thead_classes
          "bg-gray-50 dark:bg-emerald-950/20 text-gray-500 dark:text-emerald-800 uppercase text-mini tracking-widest transition-colors duration-300"
        end
      end
    end
  end
end
