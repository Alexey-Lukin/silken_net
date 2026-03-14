# frozen_string_literal: true

# app/views/components/alerts/row.rb
module Alerts
  class Row < ApplicationComponent
    def initialize(alert:)
      @alert = alert
    end

    def view_template
      tr(id: dom_id(@alert), class: row_classes) do
        td(class: "p-4") { severity_badge }
        td(class: "p-4 text-mini uppercase text-gray-400 tracking-widest") { @alert.alert_type.to_s.humanize }
        td(class: "p-4 text-emerald-500") { "#{@alert.cluster&.name} // #{@alert.tree&.did || 'System'}" }
        td(class: "p-4 text-gray-400") { @alert.message }
        td(class: "p-4 text-tiny text-gray-600") { @alert.created_at.strftime("%H:%M:%S") }
        td(class: "p-4 text-right") { action_button }
      end
    end

    private

    def severity_badge
      color = case @alert.severity.to_s
      when "critical" then "bg-status-danger text-status-danger-text animate-pulse"
      when "medium" then "bg-status-warning text-status-warning-text"
      when "low" then "bg-emerald-900 text-emerald-200"
      else "bg-zinc-900 text-zinc-200"
      end
      span(
        role: "status",
        aria_label: "Severity: #{@alert.severity}",
        class: tokens("px-2 py-0.5 rounded-sm text-mini uppercase font-bold", color)
      ) { @alert.severity }
    end

    def action_button
      if @alert.status_resolved?
        span(class: "text-emerald-700 text-mini uppercase tracking-widest", role: "status") { "V Resolved" }
      else
        # Форма для "Втихомирення" через Turbo Stream
        button_to(
          "Acknowledge & Resolve →",
          resolve_api_v1_alert_path(@alert),
          method: :patch,
          aria: { label: "Resolve alert ##{@alert.id}" },
          class: resolve_button_classes,
          data: { turbo_confirm: "Ви підтверджуєте локалізацію загрози ##{@alert.id}?" }
        )
      end
    end

    def row_classes
      tokens(
        "transition-all duration-700",
        "bg-emerald-950/5 opacity-40": @alert.status_resolved?,
        "hover:bg-emerald-950/10": !@alert.status_resolved?
      )
    end

    def resolve_button_classes
      "text-mini uppercase tracking-tighter border border-red-900 text-red-500 " \
        "hover:bg-red-900 hover:text-white " \
        "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-red-500 " \
        "px-3 py-1 transition-all"
    end
  end
end
