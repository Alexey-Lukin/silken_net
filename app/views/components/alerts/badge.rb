# frozen_string_literal: true

module Alerts
  class Badge < ApplicationComponent
    SEVERITY_STYLES = {
      "low"      => "bg-zinc-800 text-zinc-300",
      "medium"   => "bg-amber-900 text-amber-200",
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

      span(
        id: "alert_badge_#{@alert.id}",
        class: "px-2 py-0.5 rounded text-[10px] font-bold uppercase #{severity_class} #{status_class}"
      ) { "#{@alert.severity} — #{@alert.status}" }
    end
  end
end
