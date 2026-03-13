# frozen_string_literal: true

module Shared
  class StatCard < ApplicationComponent
    def initialize(label:, value:, sub: nil, danger: false)
      @label  = label
      @value  = value
      @sub    = sub
      @danger = danger
    end

    def view_template
      div(class: "p-6 border border-emerald-900 bg-zinc-950") do
        p(class: "text-[10px] uppercase tracking-widest text-emerald-700 mb-4") { @label }
        div(class: "flex items-baseline space-x-2") do
          span(class: tokens("text-4xl font-light", @danger ? "text-red-400" : "text-white")) { @value.to_s }
          span(class: "text-[10px] text-gray-600 font-mono") { @sub } if @sub
        end
      end
    end
  end
end
