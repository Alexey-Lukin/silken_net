# frozen_string_literal: true

module Views
  module Components
    module Reports
      class Index < ApplicationComponent
        def initialize(organization:, summary:)
          @organization = organization
          @summary = summary
        end

        def view_template
          div(class: "space-y-8 animate-in fade-in duration-700") do
            header_section
            render_performance_hero
            render_available_reports
          end
        end

        private

        def header_section
          div(class: "flex justify-between items-end mb-4") do
            div do
              h3(class: "text-[10px] uppercase tracking-[0.4em] text-emerald-700") { "📊 The Archive — Reports Hub" }
              p(class: "text-xs text-gray-600 mt-1") { "Зведена звітність для інвесторів: екологічні аудити та фінансова ефективність." }
            end
            div(class: "text-right font-mono text-[10px] text-emerald-900") do
              plain "Organization: "
              span(class: "text-emerald-500") { @organization.name }
            end
          end
        end

        def render_performance_hero
          div(class: "grid grid-cols-1 md:grid-cols-3 gap-6") do
            stat_card("Biological Assets", @summary[:total_trees], "Trees")
            stat_card("Health Score", @summary[:health_score], "Index")
            stat_card("Carbon Yield", @summary[:total_carbon_points], "SCC Total")
          end
          div(class: "grid grid-cols-1 md:grid-cols-3 gap-6 mt-6") do
            stat_card("Capital Injected", @summary[:total_invested], "SCC Invested")
            stat_card("Sectors", @summary[:total_clusters], "Clusters")
            stat_card("Threat Level", @summary[:under_threat] ? "ACTIVE" : "CLEAR", "", danger: @summary[:under_threat])
          end
        end

        def stat_card(label, value, sub, danger: false)
          div(class: "p-6 border border-emerald-900 bg-zinc-950") do
            p(class: "text-[10px] uppercase tracking-widest text-emerald-700 mb-4") { label }
            div(class: "flex items-baseline space-x-2") do
              span(class: tokens("text-4xl font-light", danger ? "text-red-400" : "text-white")) { value.to_s }
              span(class: "text-[10px] text-gray-600 font-mono") { sub }
            end
          end
        end

        def render_available_reports
          div(class: "space-y-4") do
            h3(class: "text-[10px] uppercase tracking-widest text-emerald-700") { "Available Reports" }
            div(class: "grid grid-cols-1 md:grid-cols-2 gap-6") do
              report_card(
                "Carbon Absorption Report",
                "Поглинання CO₂ та екологічний аудит.",
                helpers.carbon_absorption_api_v1_reports_path,
                "🌿"
              )
              report_card(
                "Financial Summary Report",
                "Фінансова ефективність та блокчейн-транзакції.",
                helpers.financial_summary_api_v1_reports_path,
                "💎"
              )
            end
          end
        end

        def report_card(title, description, path, icon)
          a(href: path, class: "group p-6 border border-emerald-900 bg-black hover:bg-emerald-950 transition-all duration-500 block") do
            div(class: "flex justify-between items-start mb-4") do
              span(class: "text-2xl") { icon }
              span(class: "text-[9px] text-emerald-900 uppercase group-hover:text-emerald-500 transition-colors") { "Generate →" }
            end
            h4(class: "text-sm font-light text-emerald-100 mb-2") { title }
            p(class: "text-[10px] text-gray-600") { description }
          end
        end
      end
    end
  end
end
