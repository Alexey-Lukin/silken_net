# frozen_string_literal: true

module Views
  module Shared
    module UI
      class EmptyState < ApplicationComponent
        def initialize(title:, description: nil, icon: "○", colspan: nil)
          @title       = title
          @description = description
          @icon        = icon
          @colspan     = colspan
        end

        def view_template
          if @colspan
            tr do
              td(colspan: @colspan, class: "p-10 text-center") { render_content }
            end
          else
            div(class: "col-span-full p-20 border border-dashed border-emerald-900/30 text-center") do
              render_content
            end
          end
        end

        private

        def render_content
          p(class: "text-emerald-900/60 text-lg mb-2") { @icon }
          p(class: "text-emerald-900 font-mono text-xs uppercase tracking-widest") { @title }
          if @description
            p(class: "text-gray-700 font-mono text-[10px] mt-2") { @description }
          end
        end
      end
    end
  end
end
