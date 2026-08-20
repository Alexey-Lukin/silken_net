# SPDX-License-Identifier: AGPL-3.0-or-later
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
            # [I18N.1] Повний шлях, не `t(".…")`: автоскоуп дав би
            # `views.shared.ui.action_badge.*`, а shared/ui живе під `ui.*`
            # (конвенція StatusBadge). Сама дія (@action) — технічний токен,
            # локалізується окремим рішенням (AuditLog#action, `04_04 §12.14`).
            aria_label: t("ui.action_badge.aria_label", action: @action),
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
