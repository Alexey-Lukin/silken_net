# frozen_string_literal: true

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
          render Views::Shared::UI::StatCard.new(label: "Forest Vitality", value: "#{@stats[:trees][:health_avg].to_i}%")
          render Views::Shared::UI::StatCard.new(label: "Active Soldiers", value: @stats[:trees][:active], sub: "/ #{@stats[:trees][:total]}")
          render Views::Shared::UI::StatCard.new(label: "Carbon Treasury", value: @stats[:economy][:total_scc], sub: "SCC")
          render Views::Shared::UI::StatCard.new(
            label: "Ionic Potential",
            value: "#{@stats[:energy][:avg_voltage]}mV",
            danger: @stats[:energy][:avg_voltage] < 3300
          )
        end

        # Центральна секція: Карта та Алерти
        div(class: "grid grid-cols-1 lg:grid-cols-3 gap-8") do
          # Геопросторова Матриця
          div(class: "lg:col-span-2 p-1 border border-emerald-900 bg-black h-[500px] relative group overflow-hidden") do
            # Фоновий растр
            div(class: "absolute inset-0 bg-[radial-gradient(#10b981_1px,transparent_1px)] [background-size:30px_30px] opacity-10")

            div(class: "absolute inset-0 flex flex-col items-center justify-center gap-4") do
              div(class: "h-12 w-12 border-2 border-emerald-500/20 border-t-emerald-500 rounded-full animate-spin")
              p(class: "text-emerald-900 font-mono text-tiny uppercase tracking-[0.5em]") { "Initializing Geospatial Matrix..." }
            end

            # Overlay для координат
            div(class: "absolute bottom-4 left-4 font-mono text-micro text-emerald-900") do
              "LAT: 49.4447 // LON: 32.0588 // ALT: 112m"
            end
          end

          # Стрічка подій (Live Feed)
          render_live_feed
        end
      end
    end

    private

    def render_live_feed
      div(class: "p-6 border border-emerald-900 bg-zinc-950 flex flex-col h-full") do
        div(class: "flex justify-between items-center mb-8") do
          h3(class: "text-tiny uppercase tracking-widest text-emerald-700") { "Live Transmission Feed" }
          div(class: "h-1.5 w-1.5 rounded-full bg-emerald-500 animate-ping")
        end

        div(class: "flex-1 flex flex-col gap-6 overflow-y-auto pr-2 custom-scrollbar") do
          @events.each do |event|
            render_event_row(event)
          end
        end

        a(
          href: helpers.api_v1_alerts_path,
          class: "mt-8 text-center py-2 border border-emerald-900 text-mini uppercase text-emerald-700 hover:text-emerald-400 hover:border-emerald-700 transition-all"
        ) { "Open Mission Log →" }
      end
    end

    def render_event_row(event)
      render Dashboard::EventRow.new(event: event)
    end
  end
end
