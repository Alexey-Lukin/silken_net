# app/views/components/oracle_visions/forecast_card.rb
module Views
  module Components
    module OracleVisions
      class ForecastCard < ApplicationComponent
        def initialize(insight:)
          @insight = insight
        end

        def view_template
          div(class: "p-6 border border-emerald-900 bg-zinc-950 group relative overflow-hidden") do
            # Індикатор впевненості
            div(class: "absolute top-0 right-0 p-4 font-mono text-xl", style: "color: #{confidence_color}") do
              plain "#{@insight.confidence_score}%"
            end

            header_section
            render_mini_trend
            footer_actions
          end
        end

        private

        def header_section
          div(class: "mb-4") do
            span(class: "text-[9px] px-2 py-0.5 border border-emerald-800 text-emerald-600 uppercase") { @insight.insight_type }
            h4(class: "text-lg font-light text-emerald-100 mt-2") { "Predicted Event Window" }
            p(class: "text-xs text-gray-500 font-mono") { @insight.target_date.strftime("%d.%m.%Y // %H:%M") }
          end
        end

        def render_mini_trend
          # Тут ми виводимо visual_trend_data як просту лінію
          div(class: "h-1 w-full bg-emerald-950 my-4") do
            div(class: "h-full bg-emerald-500 shadow-[0_0_10px_#10b981]", style: "width: #{@insight.confidence_score}%")
          end
          p(class: "text-[11px] text-gray-400 italic") { @insight.payload['description'] }
        end

        def footer_actions
          div(class: "mt-4 flex space-x-3") do
            button(class: "px-4 py-1 border border-emerald-500 text-[9px] uppercase text-emerald-500 hover:bg-emerald-500 hover:text-black transition-all") { "Deploy Pre-emptive Shield" }
          end
        end

        def confidence_color
          @insight.confidence_score > 85 ? "#ef4444" : "#10b981"
        end
      end
    end
  end
end
