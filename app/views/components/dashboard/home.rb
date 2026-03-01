# frozen_string_literal: true

module Views
  module Components
    module Dashboard
      class Home < ApplicationComponent
        def initialize(stats:, events:)
          @stats = stats
          @events = events
        end

        def view_template
          div(class: "space-y-10 animate-in fade-in duration-1000") do
            # Ряд головних метрик (The Four Pillars)
            div(class: "grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6") do
              render_stat_card("Forest Vitality", "#{@stats[:trees][:health_avg].to_i}%", color: "emerald")
              render_stat_card("Active Soldiers", @stats[:trees][:active], sub: "/ #{@stats[:trees][:total]}")
              render_stat_card("Carbon Treasury", @stats[:economy][:total_scc], sub: "SCC")
              render_stat_card("Ionic Potential", "#{@stats[:energy][:avg_voltage]}mV", color: energy_color)
            end

            # Центральна секція: Карта та Алерти
            div(class: "grid grid-cols-1 lg:grid-cols-3 gap-8") do
              # Геопросторова Матриця
              div(class: "lg:col-span-2 p-1 border border-emerald-900 bg-black h-[500px] relative group overflow-hidden") do
                # Фоновий растр
                div(class: "absolute inset-0 bg-[radial-gradient(#10b981_1px,transparent_1px)] [background-size:30px_30px] opacity-10")
                
                div(class: "absolute inset-0 flex flex-col items-center justify-center space-y-4") do
                  div(class: "h-12 w-12 border-2 border-emerald-500/20 border-t-emerald-500 rounded-full animate-spin")
                  p(class: "text-emerald-900 font-mono text-[10px] uppercase tracking-[0.5em]") { "Initializing Geospatial Matrix..." }
                end
                
                # Overlay для координат
                div(class: "absolute bottom-4 left-4 font-mono text-[8px] text-emerald-900") do
                  "LAT: 49.4447 // LON: 32.0588 // ALT: 112m"
                end
              end

              # Стрічка подій (Live Feed)
              render_live_feed
            end
          end
        end

        private

        def render_stat_card(label, value, sub: nil, color: "emerald")
          border_color = color == "red" ? "border-red-900" : "border-emerald-900"
          text_color = color == "red" ? "text-red-500" : "text-emerald-400"

          div(class: tokens("p-8 border bg-black shadow-2xl relative overflow-hidden group hover:border-emerald-500 transition-colors", border_color)) do
            p(class: "text-[9px] uppercase tracking-[0.3em] text-gray-600 mb-6") { label }
            div(class: "flex items-baseline space-x-3") do
              span(class: tokens("text-4xl font-extralight tracking-tighter", text_color)) { value }
              span(class: "text-xs text-emerald-900 font-mono") { sub } if sub
            end
            # Декоративний імпульс на фоні
            div(class: tokens("absolute bottom-0 left-0 h-[2px] w-full opacity-20", color == "red" ? "bg-red-500" : "bg-emerald-500"))
          end
        end

        def render_live_feed
          div(class: "p-6 border border-emerald-900 bg-zinc-950 flex flex-col h-full") do
            div(class: "flex justify-between items-center mb-8") do
              h3(class: "text-[10px] uppercase tracking-widest text-emerald-700") { "Live Transmission Feed" }
              div(class: "h-1.5 w-1.5 rounded-full bg-emerald-500 animate-ping")
            end

            div(class: "flex-1 space-y-6 overflow-y-auto pr-2 custom-scrollbar") do
              @events.each do |event|
                render_event_row(event)
              end
            end

            a(
              href: helpers.api_v1_alerts_path,
              class: "mt-8 text-center py-2 border border-emerald-900 text-[9px] uppercase text-emerald-700 hover:text-emerald-400 hover:border-emerald-700 transition-all"
            ) { "Open Mission Log →" }
          end
        end

        def render_event_row(event)
          div(class: "flex items-start space-x-4 border-l border-emerald-900/30 pl-4 py-1") do
            div(class: "flex flex-col flex-1 font-mono text-[10px]") do
              span(class: "text-emerald-900 text-[8px] mb-1") { helpers.time_ago_in_words(event.created_at) + " ago" }
              span(class: "text-gray-400 leading-relaxed") { format_event_msg(event) }
            end
          end
        end

        def format_event_msg(event)
          case event
          when EwsAlert then "Threat Detected: #{event.alert_type} in Cluster #{event.cluster.name}"
          when BlockchainTransaction then "Minted #{event.amount} SCC for #{event.wallet.tree&.did || 'System'}"
          when MaintenanceRecord then "Unit Ritual: #{event.action_type} by #{event.user.first_name}"
          else "System pulse detected"
          end
        end

        def energy_color
          @stats[:energy][:avg_voltage] < 3300 ? "red" : "emerald"
        end
      end
    end
  end
end
