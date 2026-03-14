# frozen_string_literal: true

module Views
  module Shared
    module IoT
      class MetricValue < ApplicationComponent
        DEFAULT_DISPLAY_PRECISION = 4

        def initialize(value:, unit: nil, precision: DEFAULT_DISPLAY_PRECISION)
          @value     = value
          @unit      = unit
          @precision = precision
        end

        def view_template
          span(
            class: "text-[11px] font-mono text-emerald-400 tabular-nums",
            title: full_value_text
          ) do
            plain display_value
            if @unit
              span(class: "text-emerald-700 ml-0.5") { @unit }
            end
          end
        end

        private

        def display_value
          return "—" if @value.nil?

          sprintf("%.#{@precision}f", @value)
        end

        def full_value_text
          return "No data" if @value.nil?

          full = @value.is_a?(BigDecimal) ? @value.to_s("F") : @value.to_s
          @unit ? "#{full} #{@unit}" : full
        end
      end
    end
  end
end
