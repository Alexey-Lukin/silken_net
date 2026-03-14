# frozen_string_literal: true

module Views
  module Shared
    module UI
      class MetaRow < ApplicationComponent
        def initialize(label:, value:, **attrs)
          @label = label
          @value = value
          @extra_class = attrs[:class]
        end

        def view_template
          div(class: tokens("flex justify-between gap-2", @extra_class)) do
            span(class: "text-gray-400 dark:text-gray-600") { "#{@label}:" }
            span(class: "text-gaia-primary truncate") { @value.to_s }
          end
        end
      end
    end
  end
end
