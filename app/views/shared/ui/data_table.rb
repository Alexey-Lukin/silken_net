# frozen_string_literal: true

module Views
  module Shared
    module UI
      class DataTable < ApplicationComponent
        def initialize(columns:, empty_message: nil, empty: false, **attrs)
          @columns = columns
          @empty_message = empty_message || t("ui.data_table.empty")
          @extra_class = attrs[:class]
          @empty = empty
        end

        def view_template
          div(class: tokens(wrapper_classes, @extra_class)) do
            table(class: table_classes, role: "table") do
              render_thead
              if @empty
                render_empty_state
              else
                tbody(class: "divide-y divide-gaia-border") { yield if block_given? }
              end
            end
          end
        end

        private

        def wrapper_classes
          "border border-gaia-border bg-gaia-surface shadow-sm dark:shadow-none overflow-x-auto w-full transition-colors duration-300"
        end

        def table_classes
          "w-full text-left font-mono text-compact"
        end

        def render_empty_state
          tbody do
            tr do
              td(colspan: @columns.size,
                 class: "p-8 text-center text-gaia-text-subtle text-compact") do
                @empty_message
              end
            end
          end
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
          "bg-gaia-surface-sunken text-gaia-text-muted uppercase text-mini tracking-widest transition-colors duration-300"
        end
      end
    end
  end
end
