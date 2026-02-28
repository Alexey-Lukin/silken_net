# frozen_string_literal: true

module Views
  module Components
    module Dashboard
      class Home < ApplicationComponent
        def initialize(stats:)
          @stats = stats
        end

        def view_template
          div(class: "space-y-8 animate-in fade-in duration-1000") do
            # Ряд головних метрик
            div(class: "grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6") do
              render_stat_card("Forest Vitality", "#{@stats[:trees][:health_avg].to_i}%", "pulse", color: "emerald")
              render_stat_card("Active Soldiers", @stats[:trees][:active], "shield", sub: "/ #{@stats[:trees][:total]}")
              render_stat_card("Carbon Treasury", @stats[:economy][:total_scc], "coins", sub: "SCC")
              render_stat_card("Threat Level", @stats[:security][:active_alerts], "alert", color: @stats[:security][:active_alerts] > 0 ? "red" : "emerald")
            end

            # Центральна секція: Карта та Алерти
            div(class: "grid grid-cols-1 lg:grid-cols-3 gap-8") do
              # Карта кластерів (Placeholder для Leaflet)
              div(class: "lg:col-span-2 p-1 border border-emerald-900 bg-zinc-950 h-[400px] relative group") do
                div(class: "absolute inset-0 bg-[url('https://www.transparenttextures.com/patterns/carbon-fibre.png')] opacity-20")
                div(class: "absolute inset-0 flex items-center justify-center") do
                  p(class: "text-emerald-900 font-mono text-xs uppercase tracking-[0.5em]") { "Geospatial Matrix Initializing..." }
                end
                # Тут буде ініціалізація Stimulus для мапи
              end

              # Стрічка останніх подій
              render_recent_events
            end
          end
        end

        private

        def render_stat_card(label, value, icon, sub: nil, color: "emerald")
          border_color = color == "red" ? "border-red-900" : "border-emerald-900"
          text_color = color == "red" ? "text-red-500" : "text-emerald-400"

          div(class: tokens("p-6 border bg-black shadow-lg", border_color)) do
            p(class: "text-[10px] uppercase tracking-widest text-gray-600 mb-4") { label }
            div(class: "flex items-baseline space-x-2") do
              span(class: tokens("text-3xl font-light tracking-tighter", text_color)) { value }
              span(class: "text-xs text-gray-700 font-mono") { sub } if sub
            end
          end
        end

        def render_recent_events
          div(class: "p-6 border border-emerald-900 bg-zinc-950") do
            h3(class: "text-[10px] uppercase tracking-widest text-emerald-700 mb-6") { "Live Transmission Feed" }
            div(class: "space-y-4") do
              # Приклад стрічки подій
              [
                { time: "2m ago", msg: "Queen v2.1 Sync OK", type: "system" },
                { time: "15m ago", msg: "Minted 0.042 SCC [Tree #41]", type: "economy" },
                { time: "1h ago", msg: "Baseline deviation in Sector 5", type: "alert" }
              ].each do |event|
                div(class: "flex items-start space-x-3 text-[11px] font-mono") do
                  span(class: "text-emerald-900 shrink-0") { event[:time] }
                  span(class: tokens(
                    "shrink-0 w-1 h-1 mt-1.5 rounded-full",
                    event[:type] == "alert" ? "bg-red-500" : "bg-emerald-600"
                  ))
                  span(class: "text-gray-400") { event[:msg] }
                end
              end
            end
          end
        end
      end
    end
  end
end
