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
            div(class: "col-span-full p-20 border border-dashed border-gaia-border text-center transition-colors duration-300", role: "status") do
              render_content
            end
          end
        end

        private

        def render_content
          p(class: "text-gaia-text-muted text-lg opacity-50", aria_hidden: "true") { @icon }
          p(class: "text-gaia-text-muted font-mono text-xs uppercase tracking-widest") { @title }
          if @description
            p(class: "text-gaia-text-muted font-mono text-tiny mt-2 opacity-70") { @description }
          end
        end
      end
    end
  end
end
