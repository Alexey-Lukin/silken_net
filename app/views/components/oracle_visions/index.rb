module Views
  module Components
    module OracleVisions
      class Index < ApplicationComponent
        def initialize(visions:)
          @visions = visions
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
          div(class: "p-6 border border-emerald-900 bg-black/40 backdrop-blur-md") do
            h3(class: "text-[10px] uppercase tracking-[0.5em] text-emerald-700") { "Strategic Forecast Matrix" }
            p(class: "text-2xl font-light text-emerald-400 mt-2") { "AI Confidence: 94.2%" }
          end
        end

        def render_active_simulations_feed
          div(id: "simulation_results", class: "space-y-4") do
            h4(class: "text-[10px] uppercase text-gray-600 tracking-widest") { "Active Simulations" }
            # Сюди Turbo Stream буде додавати результати
          end
        end
      end
    end
  end
end
