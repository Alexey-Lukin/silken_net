# frozen_string_literal: true

module Shared
  class MetaRow < ApplicationComponent
    def initialize(label:, value:)
      @label = label
      @value = value
    end

    def view_template
      div(class: "flex justify-between") do
        span(class: "text-gray-600") { "#{@label}:" }
        span(class: "text-emerald-400 truncate ml-2") { @value.to_s }
      end
    end
  end
end
