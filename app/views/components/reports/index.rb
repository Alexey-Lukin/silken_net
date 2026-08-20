# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Reports
  class Index < ApplicationComponent
    def initialize(organization:, summary:)
      @organization = organization
      @summary = summary
    end

    def view_template
      div(class: "space-y-8") do
        header_section
        render_performance_hero
        render_available_reports
      end
    end

    private

    def header_section
      div(class: "flex justify-between items-end mb-4") do
        div do
          h3(class: "text-tiny uppercase tracking-[0.4em] text-emerald-700") { t(".title") }
          p(class: "text-xs text-gray-600 mt-1") { t(".subtitle") }
        end
        div(class: "text-right font-mono text-tiny text-emerald-900") do
          plain "#{t('.organization')} "
          span(class: "text-emerald-500") { @organization.name }
        end
      end
    end

    def render_performance_hero
      div(class: "grid grid-cols-1 md:grid-cols-3 gap-6") do
        render Views::Shared::UI::StatCard.new(label: t(".hero.biological_assets"), value: @summary[:total_trees], sub: t(".hero.biological_assets_sub"))
        # [ARCH.84] Доти сюди їхало сире значення, і на невиміряному фонді `StatCard`
        # друкував порожній вузол — а його `aria-label` ставав «Health Score: » і
        # замовкав, тобто незрячий діставав підпис без величини (виміряно рендером).
        render Views::Shared::UI::StatCard.new(
          label: t(".hero.health_score"),
          value: @summary[:health_score] || t("ui.measurement.not_measured"),
          sub: measurement_coverage(@summary[:clusters_measured], @summary[:clusters_total]) ||
            t(".hero.health_score_sub")
        )
        render Views::Shared::UI::StatCard.new(label: t(".hero.carbon_yield"), value: @summary[:total_carbon_points], sub: t(".hero.carbon_yield_sub"))
      end
      div(class: "grid grid-cols-1 md:grid-cols-3 gap-6 mt-6") do
        render Views::Shared::UI::StatCard.new(label: t(".hero.capital_injected"), value: @summary[:total_contracted], sub: t(".hero.capital_injected_sub"))
        render Views::Shared::UI::StatCard.new(label: t(".hero.sectors"), value: @summary[:total_clusters], sub: t(".hero.sectors_sub"))
        render Views::Shared::UI::StatCard.new(label: t(".hero.threat_level"), value: @summary[:under_threat] ? t(".hero.threat_active") : t(".hero.threat_clear"), danger: @summary[:under_threat])
      end
    end

    def render_available_reports
      div(class: "space-y-4") do
        h3(class: "text-tiny uppercase tracking-widest text-emerald-700") { t(".available") }
        div(class: "grid grid-cols-1 md:grid-cols-2 gap-6") do
          report_card(
            t(".carbon.title"),
            t(".carbon.description"),
            carbon_absorption_reports_path,
            "🌿"
          )
          report_card(
            t(".financial.title"),
            t(".financial.description"),
            financial_summary_reports_path,
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
          a(href: path, class: "text-mini text-emerald-500 uppercase tracking-widest hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary-strong") { t(".actions.view") }
          a(href: "#{path}.csv", class: "text-mini text-emerald-700 uppercase tracking-widest hover:text-emerald-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary-strong") { t(".actions.csv") }
          a(href: "#{path}.pdf", class: "text-mini text-emerald-700 uppercase tracking-widest hover:text-emerald-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary-strong") { t(".actions.pdf") }
        end
      end
    end
  end
end
