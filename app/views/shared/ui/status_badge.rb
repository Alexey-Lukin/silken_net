# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Views
  module Shared
    module UI
      class StatusBadge < ApplicationComponent
        STYLES = {
          # AASM: BlockchainTransaction states
          "pending"      => "bg-status-warning text-status-warning-text",
          "processing"   => "bg-status-warning text-status-warning-text animate-pulse",
          "sent"         => "bg-status-info text-status-info-text",
          "confirmed"    => "bg-status-success text-status-success-text",
          "failed"       => "bg-status-danger text-status-danger-text",
          "manual_review" => "bg-status-warning text-status-warning-text animate-pulse",
          # AASM: ActuatorCommand states
          "issued"       => "bg-status-warning text-status-warning-text",
          "acknowledged" => "bg-status-active text-status-active-text",
          # AASM: EwsAlert states
          "active"       => "bg-status-danger text-status-danger-text",
          "resolved"     => "bg-status-neutral text-status-neutral-text opacity-50",
          "ignored"      => "bg-status-neutral text-status-neutral-text opacity-30 line-through",
          # AASM: ParametricInsurance states
          "triggered"    => "bg-status-warning text-status-warning-text animate-pulse",
          "paid"         => "bg-status-info text-status-info-text",
          "expired"      => "bg-status-neutral text-status-neutral-text",
          # AASM: NaasContract states
          "draft"        => "bg-status-neutral text-status-neutral-text",
          "fulfilled"    => "bg-status-success text-status-success-text",
          "breached"     => "bg-status-danger text-status-danger-text",
          "cancelled"    => "bg-status-neutral text-status-neutral-text opacity-50",
          # AASM: Gateway states
          "idle"         => "bg-status-neutral text-status-neutral-text",
          "updating"     => "bg-status-warning text-status-warning-text animate-pulse",
          "maintenance"  => "bg-status-info text-status-info-text",
          "faulty"       => "bg-status-danger text-status-danger-text",
          # AASM: Tree states
          "dormant"      => "bg-status-warning text-status-warning-text",
          "removed"      => "bg-status-neutral text-status-neutral-text opacity-50",
          "deceased"     => "bg-status-danger text-status-danger-text line-through",
          # AASM: Actuator states
          "offline"            => "bg-status-neutral text-status-neutral-text",
          "maintenance_needed" => "bg-status-warning text-status-warning-text",
          # Codex::Node lifecycle_status (docs/04_01 §7b)
          "mythical"   => "bg-status-info text-status-info-text",
          "extinct"    => "bg-status-neutral text-status-neutral-text opacity-50",
          "endangered" => "bg-status-warning text-status-warning-text",
          "thriving"   => "bg-status-success text-status-success-text",
          "destroyed"  => "bg-status-danger text-status-danger-text line-through",
          "unknown"    => "bg-status-neutral text-status-neutral-text"
        }.freeze

        DEFAULT_STYLE = "bg-status-neutral text-status-neutral-text"

        def initialize(status:, id: nil, **attrs)
          @status = status.to_s
          @id = id
          @extra_class = attrs[:class]
        end

        def view_template
          style = STYLES.fetch(@status, DEFAULT_STYLE)
          # i18n with safe fallback to the raw status (so DB-stored or new
          # AASM states render uniformly even before a translation lands).
          label = t("ui.status.#{@status}", default: @status)

          span(
            id: @id,
            role: "status",
            aria_label: t("ui.status.aria_label", status: label),
            class: tokens(badge_classes, style, @extra_class)
          ) { label }
        end

        private

        def badge_classes
          "px-2 py-0.5 rounded text-tiny font-bold uppercase tracking-widest"
        end
      end
    end
  end
end
