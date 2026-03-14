# frozen_string_literal: true

module Views
  module Shared
    module UI
      class ActionBadge < ApplicationComponent
        STYLES = {
          destructive: "bg-status-danger text-status-danger-text",
          mutative:    "bg-amber-900 text-amber-200",
          creative:    "bg-emerald-900 text-emerald-200",
          neutral:     "bg-zinc-900 text-zinc-400"
        }.freeze

        def initialize(action:)
          @action = action.to_s
        end

        def view_template
          span(
            role: "status",
            aria_label: "Action: #{@action}",
            class: tokens("px-2 py-0.5 text-[9px] font-bold uppercase", style_for_action)
          ) { @action }
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
  end
end
