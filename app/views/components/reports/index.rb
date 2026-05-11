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
          h3(class: "text-tiny uppercase tracking-[0.4em] text-emerald-700") { t("reports.index.title") }
          p(class: "text-xs text-gray-600 mt-1") { t("reports.index.subtitle") }
        end
        div(class: "text-right font-mono text-tiny text-emerald-900") do
          plain "#{t('reports.index.organization')} "
          span(class: "text-emerald-500") { @organization.name }
        end
      end
    end

    def render_performance_hero
      div(class: "grid grid-cols-1 md:grid-cols-3 gap-6") do
        render Views::Shared::UI::StatCard.new(label: t("reports.index.hero.biological_assets"), value: @summary[:total_trees], sub: t("reports.index.hero.biological_assets_sub"))
        render Views::Shared::UI::StatCard.new(label: t("reports.index.hero.health_score"), value: @summary[:health_score], sub: t("reports.index.hero.health_score_sub"))
        render Views::Shared::UI::StatCard.new(label: t("reports.index.hero.carbon_yield"), value: @summary[:total_carbon_points], sub: t("reports.index.hero.carbon_yield_sub"))
      end
      div(class: "grid grid-cols-1 md:grid-cols-3 gap-6 mt-6") do
        render Views::Shared::UI::StatCard.new(label: t("reports.index.hero.capital_injected"), value: @summary[:total_invested], sub: t("reports.index.hero.capital_injected_sub"))
        render Views::Shared::UI::StatCard.new(label: t("reports.index.hero.sectors"), value: @summary[:total_clusters], sub: t("reports.index.hero.sectors_sub"))
        render Views::Shared::UI::StatCard.new(label: t("reports.index.hero.threat_level"), value: @summary[:under_threat] ? t("reports.index.hero.threat_active") : t("reports.index.hero.threat_clear"), danger: @summary[:under_threat])
      end
    end

    def render_available_reports
      div(class: "space-y-4") do
        h3(class: "text-tiny uppercase tracking-widest text-emerald-700") { t("reports.index.available") }
        div(class: "grid grid-cols-1 md:grid-cols-2 gap-6") do
          report_card(
            t("reports.index.carbon.title"),
            t("reports.index.carbon.description"),
            carbon_absorption_api_v1_reports_path,
            "🌿"
          )
          report_card(
            t("reports.index.financial.title"),
            t("reports.index.financial.description"),
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
          a(href: path, class: "text-mini text-emerald-500 uppercase tracking-widest hover:underline") { t("reports.index.actions.view") }
          a(href: "#{path}.csv", class: "text-mini text-emerald-700 uppercase tracking-widest hover:text-emerald-500") { t("reports.index.actions.csv") }
          a(href: "#{path}.pdf", class: "text-mini text-emerald-700 uppercase tracking-widest hover:text-emerald-500") { t("reports.index.actions.pdf") }
        end
      end
    end
  end
end
