# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Reports
  class CarbonAbsorption < ApplicationComponent
    def initialize(organization:, data:)
      @organization = organization
      @data = data
    end

    def view_template
      div(class: "space-y-8") do
        header_section
        render_metrics
        render_data_table
        render_footer
      end
    end

    private

    def header_section
      div(class: "p-8 border border-gaia-border bg-gaia-surface shadow-2xl relative overflow-hidden") do
        div(class: "absolute top-0 right-0 p-4 text-[60px] font-bold text-emerald-900/5 select-none", aria_hidden: "true") { t(".decoration") }
        div do
          p(class: "text-tiny uppercase tracking-[0.4em] text-gaia-text-muted mb-2") { t(".title") }
          h2(class: "text-3xl font-extralight tracking-tighter text-gaia-text-strong") { @organization.name }
          p(class: "text-tiny font-mono text-gaia-text-muted mt-2") { t(".generated", at: Time.current.strftime("%d.%m.%Y %H:%M UTC")) }
        end
      end
    end

    def render_metrics
      div(class: "grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6") do
        render Views::Shared::UI::StatCard.new(label: t(".metrics.total_carbon_points"), value: @data[:total_carbon_points], sub: t(".metrics.total_carbon_points_sub"))
        render Views::Shared::UI::StatCard.new(label: t(".metrics.active_wallets"), value: @data[:wallets_count], sub: t(".metrics.active_wallets_sub"))
        render Views::Shared::UI::StatCard.new(label: t(".metrics.active_trees"), value: @data[:trees_active], sub: t(".metrics.active_trees_sub"))
        render Views::Shared::UI::StatCard.new(label: t(".metrics.total_trees"), value: @data[:trees_total], sub: t(".metrics.total_trees_sub"))
      end
    end

    def render_data_table
      div(class: "border border-gaia-border bg-gaia-surface overflow-x-auto w-full") do
        table(role: "table", class: "w-full text-left font-mono text-compact") do
          thead(class: "bg-gaia-surface-sunken text-gaia-text-subtle uppercase text-mini tracking-widest") do
            tr do
              th(scope: "col", class: "p-4") { t(".table.metric") }
              th(scope: "col", class: "p-4 text-right") { t(".table.value") }
            end
          end
          tbody(class: "divide-y divide-gaia-border") do
            data_row(t(".table.total_points"), @data[:total_carbon_points])
            data_row(t(".table.active_wallets"), @data[:wallets_count])
            data_row(t(".table.trees_online"), @data[:trees_active])
            data_row(t(".table.trees_deployed"), @data[:trees_total])
          end
        end
      end
    end

    def data_row(label, value)
      tr(class: "hover:bg-gaia-surface-sunken") do
        td(class: "p-4 text-gaia-primary-strong") { label }
        td(class: "p-4 text-right text-gaia-text-subtle") { value.to_s }
      end
    end

    def render_footer
      div(class: "text-mini text-gaia-text-muted text-right mt-2 font-mono") do
        t(".footer", at: Time.current.strftime("%Y-%m-%d %H:%M:%S UTC"), org: @organization.name)
      end
    end
  end
end
