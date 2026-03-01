# frozen_string_literal: true

module Views
  module Components
    module OracleVisions
      class Index < ApplicationComponent
        def initialize(visions:, yield_forecast:)
          @visions = visions
          @yield_forecast = yield_forecast
        end

        def view_template
          div(class: "grid grid-cols-1 xl:grid-cols-3 gap-8 animate-in zoom-in duration-700") do
            # ЛІВА ПАНЕЛЬ: Стрічка пророцтв
            div(class: "xl:col-span-2 space-y-6") do
              header_section
              @visions.each { |vision| render Views::Components::OracleVisions::ForecastCard.new(insight: vision) }
            end

            # ПРАВА ПАНЕЛЬ: Пульт Симуляції
            div(class: "space-y-6") do
              render Views::Components::OracleVisions::SimulationPanel.new
              render_active_simulations_feed
            end
          end
        end

        private

        def header_section
          div(class: "p-6 border border-emerald-900 bg-black/40 backdrop-blur-md flex justify-between items-end") do
            div do
              h3(class: "text-[10px] uppercase tracking-[0.5em] text-emerald-700") { "Strategic Forecast Matrix" }
              p(class: "text-2xl font-light text-emerald-400 mt-2") { "AI Confidence: 94.2%" }
            end

            # [FINANCIAL ENGINE VISUALIZATION]: Очікуваний врожай
            div(class: "text-right") do
              h4(class: "text-[10px] uppercase tracking-widest text-emerald-800 mb-1") { "Expected 24h Yield" }
              div(class: "flex items-baseline justify-end gap-2") do
                span(class: "text-3xl font-mono text-emerald-400 drop-shadow-[0_0_8px_rgba(52,211,153,0.5)]") do
                  @yield_forecast
                end
                span(class: "text-xs text-emerald-600 font-light italic") { "SCC" }
              end
            end
          end
        end

        def render_active_simulations_feed
          div(id: "simulation_results", class: "space-y-4") do
            div(class: "flex items-center gap-2 mb-4") do
              div(class: "w-1 h-1 bg-emerald-500 rounded-full animate-ping")
              h4(class: "text-[10px] uppercase text-gray-600 tracking-widest") { "Active Simulations" }
            end
            # Сюди Turbo Stream буде додавати результати симуляцій
          end
        end
      end
    end
  end
end
