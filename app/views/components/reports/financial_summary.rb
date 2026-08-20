# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Reports
  class FinancialSummary < ApplicationComponent
    def initialize(organization:, data:)
      @organization = organization
      @data = data
    end

    def view_template
      div(class: "space-y-8") do
        header_section
        render_metrics
        render_blockchain_breakdown
        render_network_emission
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
        render Views::Shared::UI::StatCard.new(label: t(".metrics.total_invested"), value: @data[:total_contracted], sub: t(".metrics.total_invested_sub"))
        render Views::Shared::UI::StatCard.new(label: t(".metrics.active_contracts"), value: @data[:active_contracts], sub: t(".metrics.active_contracts_sub"))
        render Views::Shared::UI::StatCard.new(label: t(".metrics.total_contracts"), value: @data[:total_contracts], sub: t(".metrics.total_contracts_sub"))
        # [ARCH.90] Внесок ЦІЄЇ організації у страховий пул. Підпис несе одиницю
        # (USDC), бо сусіди в цьому ж звіті деноміновані інакше — вісь ARCH.88.
        render Views::Shared::UI::StatCard.new(label: t(".metrics.insurance_premiums"), value: @data[:insurance_premiums_paid_usdc], sub: t(".metrics.insurance_premiums_sub"))
      end
    end

    # [ARCH.90, присуд founder 2026-08-13] Блок існував у CSV/PDF/JSON і НЕ існував
    # тут — при тому, що кожен HTML-запит за нього платив (GraphQL-раундтрип у
    # subgraph будувався в спільному `@data` і викидався). Тепер він рендериться, і
    # 🔴 несе ЯВНЕ застереження, що числа протокольні: доти єдиною підказкою було
    # слово «Network» у заголовку, а поруч у тій самій секції стояла премія —
    # платформенний агрегат, який читався як власний. Премія звідси пішла нагору,
    # у метрики, вже скоупленою.
    def render_network_emission
      ne = @data[:network_emission]
      return if ne.blank?

      div(class: "space-y-4") do
        h3(class: "text-tiny uppercase tracking-widest text-gaia-text-muted") { t(".emission.title") }
        p(class: "text-mini text-gaia-text-muted font-mono") { t(".emission.disclaimer") }
        div(class: "border border-gaia-border bg-gaia-surface overflow-x-auto w-full") do
          table(role: "table", class: "w-full text-left font-mono text-compact") do
            thead(class: "bg-gaia-surface-sunken text-gaia-text-subtle uppercase text-mini tracking-widest") do
              tr do
                th(scope: "col", class: "p-4") { t(".breakdown.category") }
                th(scope: "col", class: "p-4 text-right") { t(".breakdown.count") }
              end
            end
            tbody(class: "divide-y divide-gaia-border") do
              tx_row(t(".emission.total_minted"), ne[:total_minted_scc])
              tx_row(t(".emission.total_burned"), ne[:total_burned_scc])
              tx_row(t(".emission.net_deflation"), ne[:net_deflation])
            end
          end
        end
      end
    end

    def render_blockchain_breakdown
      tx = @data[:blockchain_transactions]

      div(class: "space-y-4") do
        h3(class: "text-tiny uppercase tracking-widest text-gaia-text-muted") { t(".breakdown.title") }
        div(class: "border border-gaia-border bg-gaia-surface overflow-x-auto w-full") do
          table(role: "table", class: "w-full text-left font-mono text-compact") do
            thead(class: "bg-gaia-surface-sunken text-gaia-text-subtle uppercase text-mini tracking-widest") do
              tr do
                th(scope: "col", class: "p-4") { t(".breakdown.category") }
                th(scope: "col", class: "p-4 text-right") { t(".breakdown.count") }
              end
            end
            tbody(class: "divide-y divide-gaia-border") do
              tx_row(t(".breakdown.total_transactions"), tx[:total])
              tx_row(t(".breakdown.confirmed"), tx[:confirmed], "text-gaia-text")
              tx_row(t(".breakdown.pending"), tx[:pending], "text-status-warning-text")
              tx_row(t(".breakdown.failed"), tx[:failed], "text-status-danger-accent")
            end
          end
        end
      end
    end

    def tx_row(label, count, color_class = nil)
      tr(class: "hover:bg-gaia-surface-sunken") do
        td(class: tokens("p-4", color_class || "text-gaia-primary-strong")) { label }
        # [ARCH.103] `.to_s` на `nil` дає ПОРОЖНЮ комірку під підписом «Total Minted» —
        # мовчання, яке читається як нуль. `nil` тут приходить із fallback'у subgraph
        # (`NETWORK_EMISSION_DEFAULTS`) і означає «не виміряно», а не «нуль подій».
        td(class: tokens("p-4 text-right font-bold", color_class || "text-gaia-text-subtle")) do
          count.nil? ? t("ui.measurement.not_measured") : count.to_s
        end
      end
    end

    def render_footer
      div(class: "text-mini text-gaia-text-muted text-right mt-2 font-mono") do
        t(".footer", at: Time.current.strftime("%Y-%m-%d %H:%M:%S UTC"), org: @organization.name)
      end
    end
  end
end
