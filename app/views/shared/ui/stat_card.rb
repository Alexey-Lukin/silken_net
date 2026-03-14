# frozen_string_literal: true

module Views
  module Shared
    module UI
      class StatCard < ApplicationComponent
        def initialize(label:, value:, sub: nil, danger: false, **attrs)
          @label  = label
          @value  = value
          @sub    = sub
          @danger = danger
          @extra_class = attrs[:class]
        end

        def view_template
          div(
            class: tokens(card_classes, @extra_class),
            role: "group",
            aria_label: @label
          ) do
            p(class: label_classes) { @label }
            div(class: "flex items-baseline gap-2") do
              span(
                class: tokens("text-4xl font-light leading-tight", "text-status-danger-accent": @danger, "text-gray-900 dark:text-white": !@danger),
                aria_label: "#{@label}: #{@value}#{@sub ? " #{@sub}" : ""}"
              ) { @value.to_s }
              span(class: "text-tiny text-gray-400 dark:text-gray-600 font-mono") { @sub } if @sub
            end
          end
        end

        private

        def card_classes
          "p-6 border border-gray-200 dark:border-emerald-900 bg-white dark:bg-zinc-950 transition-colors duration-300"
        end

        def label_classes
          "text-tiny uppercase tracking-widest text-gray-400 dark:text-emerald-700"
        end
      end
    end
  end
end
