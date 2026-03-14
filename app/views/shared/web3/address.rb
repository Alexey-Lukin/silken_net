# frozen_string_literal: true

module Views
  module Shared
    module Web3
      class Address < ApplicationComponent
        PREFIX_LENGTH = 6
        SUFFIX_LENGTH = 4

        def initialize(address:, fallback: "NOT_PROVISIONED")
          @address  = address
          @fallback = fallback
        end

        def view_template
          if @address.present?
            span(
              class: "inline-flex items-center gap-1",
              data: { controller: "clipboard", clipboard_content_value: @address }
            ) do
              span(
                class: "text-compact font-mono text-emerald-500 break-all leading-relaxed",
                title: @address
              ) { truncated_address }
              button(
                type: "button",
                class: copy_button_classes,
                title: "Copy address",
                aria_label: "Copy address #{truncated_address} to clipboard",
                data: { action: "clipboard#copy", clipboard_target: "button" }
              ) { copy_icon }
            end
          else
            span(class: "text-compact font-mono text-gray-700 italic") { @fallback }
          end
        end

        private

        def truncated_address
          return @address if @address.length <= PREFIX_LENGTH + SUFFIX_LENGTH

          "#{@address.first(PREFIX_LENGTH)}…#{@address.last(SUFFIX_LENGTH)}"
        end

        def copy_button_classes
          "text-emerald-700 hover:text-emerald-300 " \
            "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-emerald-500 " \
            "transition-colors duration-200 cursor-pointer"
        end

        def copy_icon
          svg(
            xmlns: "http://www.w3.org/2000/svg",
            fill: "none",
            viewbox: "0 0 24 24",
            stroke_width: "1.5",
            stroke: "currentColor",
            class: "w-3 h-3",
            aria_hidden: "true"
          ) do |s|
            s.path(
              stroke_linecap: "round",
              stroke_linejoin: "round",
              d: "M15.666 3.888A2.25 2.25 0 0 0 13.5 2.25h-3c-1.03 0-1.9.693-2.166 " \
                 "1.638m7.332 0c.055.194.084.4.084.612v0a.75.75 0 0 1-.75.75H9.75a.75.75 " \
                 "0 0 1-.75-.75v0c0-.212.03-.418.084-.612m7.332 0c.646.049 1.288.11 " \
                 "1.927.184 1.1.128 1.907 1.077 1.907 2.185V19.5a2.25 2.25 0 0 " \
                 "1-2.25 2.25H6.75A2.25 2.25 0 0 1 4.5 19.5V6.257c0-1.108.806-2.057 " \
                 "1.907-2.185a48.208 48.208 0 0 1 1.927-.184"
            )
          end
        end
      end
    end
  end
end
