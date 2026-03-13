# frozen_string_literal: true

module Shared
  class ActionBadge < ApplicationComponent
    STYLES = {
      destructive: "bg-red-900 text-red-200",
      mutative:    "bg-amber-900 text-amber-200",
      creative:    "bg-emerald-900 text-emerald-200",
      neutral:     "bg-zinc-900 text-zinc-400"
    }.freeze

    def initialize(action:)
      @action = action.to_s
    end

    def view_template
      span(class: "px-2 py-0.5 text-[9px] font-bold uppercase #{style_for_action}") { @action }
    end

    private

    def style_for_action
      case @action
      when /delete|destroy|remove/ then STYLES[:destructive]
      when /update|modify|change/ then STYLES[:mutative]
      when /create|add|new/ then STYLES[:creative]
      else STYLES[:neutral]
      end
    end
  end
end
