# frozen_string_literal: true

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
          h3(class: "text-tiny uppercase tracking-[0.4em] text-emerald-700") { "📊 The Archive — Reports Hub" }
          p(class: "text-xs text-gray-600 mt-1") { "Зведена звітність для інвесторів: екологічні аудити та фінансова ефективність." }
        end
        div(class: "text-right font-mono text-tiny text-emerald-900") do
          plain "Organization: "
          span(class: "text-emerald-500") { @organization.name }
        end
      end
    end

    def render_performance_hero
      div(class: "grid grid-cols-1 md:grid-cols-3 gap-6") do
        render Views::Shared::UI::StatCard.new(label: "Biological Assets", value: @summary[:total_trees], sub: "Trees")
        render Views::Shared::UI::StatCard.new(label: "Health Score", value: @summary[:health_score], sub: "Index")
        render Views::Shared::UI::StatCard.new(label: "Carbon Yield", value: @summary[:total_carbon_points], sub: "SCC Total")
      end
      div(class: "grid grid-cols-1 md:grid-cols-3 gap-6 mt-6") do
        render Views::Shared::UI::StatCard.new(label: "Capital Injected", value: @summary[:total_invested], sub: "SCC Invested")
        render Views::Shared::UI::StatCard.new(label: "Sectors", value: @summary[:total_clusters], sub: "Clusters")
        render Views::Shared::UI::StatCard.new(label: "Threat Level", value: @summary[:under_threat] ? "ACTIVE" : "CLEAR", danger: @summary[:under_threat])
      end
    end

    def render_available_reports
      div(class: "space-y-4") do
        h3(class: "text-tiny uppercase tracking-widest text-emerald-700") { "Available Reports" }
        div(class: "grid grid-cols-1 md:grid-cols-2 gap-6") do
          report_card(
            "Carbon Absorption Report",
            "Поглинання CO₂ та екологічний аудит.",
            carbon_absorption_api_v1_reports_path,
            "🌿"
          )
          report_card(
            "Financial Summary Report",
            "Фінансова ефективність та блокчейн-транзакції.",
            financial_summary_api_v1_reports_path,
            "💎"
          )
        end
      end
    end

    def report_card(title, description, path, icon)
      div(class: "group p-6 border border-emerald-900 bg-black hover:bg-emerald-950 transition-all duration-500") do
        div(class: "flex justify-between items-start mb-4") do
          span(class: "text-2xl") { icon }
        end
        h4(class: "text-sm font-light text-emerald-100 mb-2") { title }
        p(class: "text-tiny text-gray-600 mb-4") { description }
        div(class: "flex items-center gap-4 pt-4 border-t border-emerald-900/30") do
          a(href: path, class: "text-mini text-emerald-500 uppercase tracking-widest hover:underline") { "View →" }
          a(href: "#{path}.csv", class: "text-mini text-emerald-700 uppercase tracking-widest hover:text-emerald-500") { "CSV ↓" }
          a(href: "#{path}.pdf", class: "text-mini text-emerald-700 uppercase tracking-widest hover:text-emerald-500") { "PDF ↓" }
        end
      end
    end
  end
end
