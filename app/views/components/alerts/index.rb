module Views
  module Components
    module Alerts
      class Index < ApplicationComponent
        def initialize(alerts:)
          @alerts = alerts
        end

        def view_template
          div(class: "space-y-6 animate-in fade-in duration-500") do
            header_section
            
            div(class: "border border-emerald-900 bg-black overflow-hidden") do
              table(class: "w-full text-left font-mono text-[11px]") do
                thead(class: "bg-emerald-950/20 text-emerald-800 uppercase text-[9px] tracking-widest") do
                  tr do
                    th(class: "p-4") { "Severity" }
                    th(class: "p-4") { "Source" }
                    th(class: "p-4") { "Event / Message" }
                    th(class: "p-4") { "Timestamp" }
                    th(class: "p-4 text-right") { "Command" }
                  end
                end
                tbody(id: "alerts_feed", class: "divide-y divide-emerald-900/30") do
                  @alerts.each { |alert| render Views::Components::Alerts::Row.new(alert: alert) }
                end
              end
            end
          end
        end

        private

        def header_section
          div(class: "flex justify-between items-end mb-4") do
            div do
              h3(class: "text-[10px] uppercase tracking-[0.4em] text-emerald-700") { "Active Threats Matrix" }
              p(class: "text-xs text-gray-600 mt-1") { "Monitoring live telemetry for anomalies and baseline deviations." }
            end
            # Фільтри (спрощено)
            div(class: "flex space-x-2") do
              ['critical', 'warning', 'info'].each do |s|
                span(class: "px-2 py-0.5 border border-emerald-900 text-[9px] text-emerald-900 uppercase") { s }
              end
            end
          end
        end
      end
    end
  end
end
