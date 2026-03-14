# frozen_string_literal: true

module Views
  module Shared
    module UI
      class ActionBadge < ApplicationComponent
        STYLES = {
          destructive: "bg-status-danger text-status-danger-text",
          mutative:    "bg-status-warning text-status-warning-text",
          creative:    "bg-status-active text-status-active-text",
          neutral:     "bg-status-neutral text-status-neutral-text"
        }.freeze

        def initialize(action:, **attrs)
          @action = action.to_s
          @extra_class = attrs[:class]
        end

        def view_template
          span(
            role: "status",
            aria_label: "Action: #{@action}",
            class: tokens(badge_classes, style_for_action, @extra_class)
          ) { @action }
        end

        private

        def badge_classes
          "px-2 py-0.5 text-mini font-bold uppercase tracking-widest"
        end

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
