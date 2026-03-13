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
        div(class: "absolute top-0 right-0 p-4 text-[60px] font-bold text-emerald-900/5 select-none") { "FIN" }
        div do
          p(class: "text-[10px] uppercase tracking-[0.4em] text-emerald-700 mb-2") { "💎 Financial Summary Report" }
          h2(class: "text-3xl font-extralight tracking-tighter text-white") { @organization.name }
          p(class: "text-[10px] font-mono text-gray-600 mt-2") { "Generated: #{Time.current.strftime('%d.%m.%Y %H:%M UTC')}" }
        end
      end
    end

    def render_metrics
      div(class: "grid grid-cols-1 md:grid-cols-3 gap-6") do
        render Views::Shared::UI::StatCard.new(label: "Total Invested", value: @data[:total_invested], sub: "SCC")
        render Views::Shared::UI::StatCard.new(label: "Active Contracts", value: @data[:active_contracts], sub: "NaaS")
        render Views::Shared::UI::StatCard.new(label: "Total Contracts", value: @data[:total_contracts], sub: "Lifetime")
      end
    end

    def render_blockchain_breakdown
      tx = @data[:blockchain_transactions]

      div(class: "space-y-4") do
        h3(class: "text-[10px] uppercase tracking-widest text-emerald-700") { "Blockchain Transactions Breakdown" }
        div(class: "border border-emerald-900 bg-black overflow-hidden") do
          table(class: "w-full text-left font-mono text-[11px]") do
            thead(class: "bg-emerald-950/20 text-emerald-800 uppercase text-[9px] tracking-widest") do
              tr do
                th(class: "p-4") { "Category" }
                th(class: "p-4 text-right") { "Count" }
              end
            end
            tbody(class: "divide-y divide-emerald-900/30") do
              tx_row("Total Transactions", tx[:total])
              tx_row("Confirmed", tx[:confirmed], "text-emerald-400")
              tx_row("Pending", tx[:pending], "text-amber-400")
              tx_row("Failed", tx[:failed], "text-red-400")
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
      div(class: "text-[9px] text-gray-600 text-right mt-2 font-mono") do
        "Report generated at #{Time.current.strftime('%Y-%m-%d %H:%M:%S UTC')} for #{@organization.name}"
      end
    end
  end
end
