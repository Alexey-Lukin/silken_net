# frozen_string_literal: true

module Alerts
  class Index < ApplicationComponent
    def initialize(alerts:, pagy:)
      @alerts = alerts
      @pagy = pagy
    end

    def view_template
      div(class: "space-y-6 animate-in fade-in duration-500") do
        header_section

        div(class: "border border-emerald-900 bg-black overflow-x-auto w-full") do
          table(class: "w-full text-left font-mono text-compact min-w-[640px]", role: "table") do
            thead(class: "bg-emerald-950/20 text-emerald-800 uppercase text-mini tracking-widest") do
              tr do
                th(scope: "col", class: "p-4") { "Severity" }
                th(scope: "col", class: "p-4") { "Source" }
                th(scope: "col", class: "p-4") { "Event / Message" }
                th(scope: "col", class: "p-4") { "Timestamp" }
                th(scope: "col", class: "p-4 text-right") { "Command" }
              end
            end
            tbody(id: "alerts_feed", class: "divide-y divide-emerald-900/30") do
              @alerts.each { |alert| render Alerts::Row.new(alert: alert) }
            end
          end
        end

        render Views::Shared::UI::Pagination.new(
          pagy: @pagy,
          url_helper: ->(page:) { helpers.api_v1_alerts_path(page: page) }
        )
      end
    end

    private

    def header_section
      div(class: "flex justify-between items-end mb-4") do
        div do
          h3(class: "text-tiny uppercase tracking-[0.4em] text-emerald-700") { "Active Threats Matrix" }
          p(class: "text-xs text-gray-600 mt-1") { "Monitoring live telemetry for anomalies and baseline deviations." }
        end
        # Фільтри (спрощено)
        div(class: "flex gap-2") do
          a(
            href: helpers.api_v1_alerts_path,
            aria_label: "Show all alerts",
            class: "px-2 py-0.5 border border-emerald-900 text-mini text-emerald-700 uppercase hover:border-emerald-500 hover:text-emerald-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-emerald-500 transition-all"
          ) { "all" }
          %w[critical medium low].each do |s|
            a(
              href: helpers.api_v1_alerts_path(severity: s),
              aria_label: "Filter alerts by #{s} severity",
              class: "px-2 py-0.5 border border-emerald-900 text-mini text-emerald-900 uppercase hover:border-emerald-500 hover:text-emerald-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-emerald-500 transition-all"
            ) { s }
          end
        end
      end
    end
  end
end
