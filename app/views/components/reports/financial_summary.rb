# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Reports
  class FinancialSummary < ApplicationComponent
    def initialize(organization:, data:)
      @organization = organization
      @data = data
    end

    def view_template
      div(class: "space-y-8 animate-in fade-in duration-500") do
        header_section
        render_metrics
        render_blockchain_breakdown
        render_footer
      end
    end

    private

    def header_section
      div(class: "p-8 border border-emerald-900 bg-black shadow-2xl relative overflow-hidden") do
        div(class: "absolute top-0 right-0 p-4 text-[60px] font-bold text-emerald-900/5 select-none", aria_hidden: "true") { t(".decoration") }
        div do
          p(class: "text-tiny uppercase tracking-[0.4em] text-emerald-700 mb-2") { t(".title") }
          h2(class: "text-3xl font-extralight tracking-tighter text-white") { @organization.name }
          p(class: "text-tiny font-mono text-gray-600 mt-2") { t(".generated", at: Time.current.strftime("%d.%m.%Y %H:%M UTC")) }
        end
      end
    end

    def render_metrics
      div(class: "grid grid-cols-1 md:grid-cols-3 gap-6") do
        render Views::Shared::UI::StatCard.new(label: t(".metrics.total_invested"), value: @data[:total_contracted], sub: t(".metrics.total_invested_sub"))
        render Views::Shared::UI::StatCard.new(label: t(".metrics.active_contracts"), value: @data[:active_contracts], sub: t(".metrics.active_contracts_sub"))
        render Views::Shared::UI::StatCard.new(label: t(".metrics.total_contracts"), value: @data[:total_contracts], sub: t(".metrics.total_contracts_sub"))
      end
    end

    def render_blockchain_breakdown
      tx = @data[:blockchain_transactions]

      div(class: "space-y-4") do
        h3(class: "text-tiny uppercase tracking-widest text-emerald-700") { t(".breakdown.title") }
        div(class: "border border-emerald-900 bg-black overflow-x-auto w-full") do
          table(role: "table", class: "w-full text-left font-mono text-compact") do
            thead(class: "bg-emerald-950/20 text-emerald-800 uppercase text-mini tracking-widest") do
              tr do
                th(scope: "col", class: "p-4") { t(".breakdown.category") }
                th(scope: "col", class: "p-4 text-right") { t(".breakdown.count") }
              end
            end
            tbody(class: "divide-y divide-emerald-900/30") do
              tx_row(t(".breakdown.total_transactions"), tx[:total])
              tx_row(t(".breakdown.confirmed"), tx[:confirmed], "text-emerald-400")
              tx_row(t(".breakdown.pending"), tx[:pending], "text-status-warning-text")
              tx_row(t(".breakdown.failed"), tx[:failed], "text-red-400")
            end
          end
        end
      end
    end

    def tx_row(label, count, color_class = nil)
      tr(class: "hover:bg-emerald-950/10") do
        td(class: tokens("p-4", color_class || "text-emerald-500")) { label }
        td(class: tokens("p-4 text-right font-bold", color_class || "text-gray-300")) { count.to_s }
      end
    end

    def render_footer
      div(class: "text-mini text-gray-600 text-right mt-2 font-mono") do
        t(".footer", at: Time.current.strftime("%Y-%m-%d %H:%M:%S UTC"), org: @organization.name)
      end
    end
  end
end
