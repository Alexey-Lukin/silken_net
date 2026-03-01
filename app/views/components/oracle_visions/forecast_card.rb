# frozen_string_literal: true

module Views
  module Components
    module OracleVisions
      class ForecastCard < ApplicationComponent
        def initialize(insight:)
          @insight = insight
        end

        def view_template
          div(class: "p-6 border border-emerald-900 bg-zinc-950 group relative overflow-hidden transition-all hover:border-emerald-500") do
            # Неоновий індикатор впевненості Оракула
            div(class: "absolute top-0 right-0 p-4 font-mono text-2xl opacity-40 group-hover:opacity-100 transition-opacity", style: "color: #{confidence_color}") do
              plain "#{@insight.confidence_score}%"
            end

            header_section
            render_mini_trend
            impact_assessment # Новий блок оцінки впливу на SCC
            footer_actions
          end
        end

        private

        def header_section
          div(class: "mb-4") do
            span(class: "text-[9px] px-2 py-0.5 border border-emerald-800 text-emerald-600 uppercase tracking-tighter") { @insight.insight_type }
            h4(class: "text-lg font-light text-emerald-100 mt-2") { "Predicted Event Window" }
            p(class: "text-[10px] text-gray-500 font-mono flex items-center gap-2") do
              i(class: "ph ph-clock")
              plain @insight.target_date.strftime("%d.%m.%Y // %H:%M UTC")
            end
          end
        end

        def render_mini_trend
          div(class: "h-1 w-full bg-emerald-950 my-4") do
            div(class: "h-full shadow-[0_0_15px_#10b981] transition-all duration-1000", 
                style: "width: #{@insight.confidence_score}%; background-color: #{confidence_color}")
          end
          p(class: "text-[11px] text-gray-400 italic leading-relaxed") { @insight.payload['description'] }
        end

        def impact_assessment
          # Якщо це негативна подія (стрес), показуємо червоним
          div(class: "mt-4 pt-4 border-t border-emerald-900/50 flex justify-between items-center") do
            span(class: "text-[9px] uppercase text-gray-600") { "Economic Impact" }
            span(class: "text-xs font-mono #{impact_text_color}") do
              plain "#{@insight.payload['yield_impact'] || '-0.04%'} SCC"
            end
          end
        end

        def footer_actions
          div(class: "mt-6 flex space-x-3") do
            button(class: "px-4 py-1.5 border border-emerald-500 text-[9px] uppercase text-emerald-500 hover:bg-emerald-500 hover:text-black transition-all font-bold") do
              "Deploy Pre-emptive Shield"
            end
            button(class: "px-4 py-1.5 border border-zinc-700 text-[9px] uppercase text-zinc-500 hover:border-zinc-500 transition-all") do
              "Ignore Singularity"
            end
          end
        end

        def confidence_color
          return "#ef4444" if @insight.confidence_score > 90 && @insight.insight_type == "emergency"
          "#10b981"
        end

        def impact_text_color
          @insight.payload['yield_impact'].to_f < 0 ? "text-red-500" : "text-emerald-500"
        end
      end
    end
  end
end
