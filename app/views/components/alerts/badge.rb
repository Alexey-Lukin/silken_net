# frozen_string_literal: true

module Alerts
  class Badge < ApplicationComponent
    SEVERITY_STYLES = {
      "low"      => "bg-zinc-800 text-zinc-300",
      "medium"   => "bg-status-warning text-status-warning-text",
      "critical" => "bg-red-900 text-red-200 animate-pulse"
    }.freeze

    STATUS_STYLES = {
      "active"   => "",
      "resolved" => "opacity-50",
      "ignored"  => "opacity-30 line-through"
    }.freeze

    def initialize(alert:)
      @alert = alert
    end

    def view_template
      severity_class = SEVERITY_STYLES.fetch(@alert.severity.to_s, "bg-zinc-800 text-zinc-300")
      status_class   = STATUS_STYLES.fetch(@alert.status.to_s, "")

      severity_label = I18n.t("alerts.badge.severities.#{@alert.severity}", default: @alert.severity.to_s)
      status_label   = I18n.t("alerts.badge.statuses.#{@alert.status}", default: @alert.status.to_s)

      span(
        id: "alert_badge_#{@alert.id}",
        class: tokens("px-2 py-0.5 rounded text-tiny font-bold uppercase", severity_class, status_class)
      ) { t("alerts.badge.summary", severity: severity_label, status: status_label) }
    end
  end
end
