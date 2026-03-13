# frozen_string_literal: true

module Shared
  class DataTable < ApplicationComponent
    def initialize(columns:, empty_message: "No records found.", &block)
      @columns = columns
      @empty_message = empty_message
      @rows_block = block
    end

    def view_template
      div(class: "border border-emerald-900 bg-black overflow-hidden") do
        table(class: "w-full text-left font-mono text-[11px]") do
          render_thead
          tbody(class: "divide-y divide-emerald-900/30", &@rows_block)
        end
      end
    end

    private

    def render_thead
      thead(class: "bg-emerald-950/20 text-emerald-800 uppercase text-[9px] tracking-widest") do
        tr do
          @columns.each do |col|
            th(class: tokens("p-4", col[:class])) { col[:label] }
          end
        end
      end
    end
  end
end
