# frozen_string_literal: true

module Views
  module Shared
    module UI
      class ThemeSwitcher < ApplicationComponent
        def view_template
          div(data: { controller: "theme" }) do
            button(
              type: "button",
              aria_label: "Toggle light/dark theme",
              class: "p-2 border border-gaia-border text-gaia-text-muted " \
                     "hover:text-gaia-primary hover:border-gaia-primary " \
                     "focus:outline-none focus:ring-2 focus:ring-gaia-primary " \
                     "transition-colors duration-300",
              data: { action: "click->theme#toggle", theme_target: "icon" }
            ) do
              # Default: moon icon (placeholder replaced by Stimulus on connect)
              raw_svg_moon
            end
          end
        end

        private

        def raw_svg_moon
          svg(
            xmlns: "http://www.w3.org/2000/svg",
            class: "h-5 w-5",
            fill: "none",
            viewBox: "0 0 24 24",
            stroke: "currentColor",
            stroke_width: "2"
          ) do |s|
            s.path(
              stroke_linecap: "round",
              stroke_linejoin: "round",
              d: "M20.354 15.354A9 9 0 018.646 3.646 9.005 9.005 0 0012 21a9.005 9.005 0 008.354-5.646z"
            )
          end
        end
      end
    end
  end
end
