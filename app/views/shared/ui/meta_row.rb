# frozen_string_literal: true

module Views
  module Shared
    module UI
      class MetaRow < ApplicationComponent
        def initialize(label:, value:)
          @label = label
          @value = value
        end

        def view_template
          div(class: "flex justify-between") do
            span(class: "text-gray-400 dark:text-gray-600") { "#{@label}:" }
            span(class: "text-gaia-primary truncate ml-2") { @value.to_s }
          end
        end
      end
    end
  end
end
