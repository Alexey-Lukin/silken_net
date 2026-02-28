# app/views/components/alerts/row.rb
module Views
  module Components
    module Alerts
      class Row < ApplicationComponent
        def initialize(alert:)
          @alert = alert
        end

        def view_template
          tr(id: "alert_#{@alert.id}", class: tokens("transition-all duration-700", @alert.resolved? ? "bg-emerald-950/5 opacity-40" : "hover:bg-emerald-950/10")) do
            td(class: "p-4") { severity_badge }
            td(class: "p-4 text-emerald-500") { "#{@alert.cluster&.name} // #{@alert.tree&.did || 'System'}" }
            td(class: "p-4 text-gray-400") { @alert.message }
            td(class: "p-4 text-[10px] text-gray-600") { @alert.created_at.strftime("%H:%M:%S") }
            td(class: "p-4 text-right") { action_button }
          end
        end

        private

        def severity_badge
          color = case @alert.severity
                  when 'critical' then "bg-red-900 text-red-200"
                  when 'warning' then "bg-amber-900 text-amber-200"
                  else "bg-emerald-900 text-emerald-200"
                  end
          span(class: "px-2 py-0.5 rounded-sm text-[9px] uppercase font-bold #{color}") { @alert.severity }
        end

        def action_button
          if @alert.resolved?
            span(class: "text-emerald-700 text-[9px] uppercase tracking-widest") { "V Resolved" }
          else
            # Форма для "Втихомирення" через Turbo Stream
            button_to(
              "Acknowledge & Resolve →",
              helpers.resolve_api_v1_alert_path(@alert),
              method: :patch,
              class: "text-[9px] uppercase tracking-tighter border border-red-900 text-red-500 hover:bg-red-900 hover:text-white px-3 py-1 transition-all",
              data: { turbo_confirm: "Ви підтверджуєте локалізацію загрози ##{@alert.id}?" }
            )
          end
        end
      end
    end
  end
end
