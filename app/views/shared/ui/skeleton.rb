# frozen_string_literal: true

module Views
  module Shared
    module UI
      class Skeleton < ApplicationComponent
        VARIANTS = {
          balance: [
            { height: "h-4", width: "w-32" },
            { height: "h-16", width: "w-64" },
            { height: "h-3", width: "w-48" }
          ],
          text: [
            { height: "h-4", width: "w-full" }
          ],
          card: [
            { height: "h-4", width: "w-1/3" },
            { height: "h-8", width: "w-2/3" },
            { height: "h-4", width: "w-1/2" }
          ]
        }.freeze

        def initialize(variant: :balance, lines: nil, **attrs)
          @variant = variant.to_sym
          @lines = lines
          @extra_class = attrs[:class]
        end

        def view_template
          div(
            class: tokens(container_classes, @extra_class),
            role: "status",
            aria_label: "Loading…"
          ) do
            skeleton_lines.each do |line|
              div(class: tokens("rounded bg-gaia-border animate-pulse", line[:height], line[:width]))
            end
          end
        end

        private

        def skeleton_lines
          if @lines
            Array.new(@lines) { |i| { height: "h-4", width: i.zero? ? "w-2/3" : "w-full" } }
          else
            VARIANTS.fetch(@variant, VARIANTS[:text])
          end
        end

        def container_classes
          "space-y-4 p-10 border border-gaia-border bg-gaia-surface"
        end
      end
    end
  end
end
