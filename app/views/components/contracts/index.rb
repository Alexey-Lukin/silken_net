# frozen_string_literal: true

module Contracts
  class Index < ApplicationComponent
    def initialize(contracts:, stats:, pagy:)
      @contracts = contracts
      @stats = stats
      @pagy = pagy
    end

    def view_template
      div(class: "space-y-8 animate-in fade-in duration-700") do
        render_stats_hero

        div(class: "space-y-4") do
          h3(class: "text-tiny uppercase tracking-[0.4em] text-emerald-700") { "Active Asset Portfolio" }

          div(class: "border border-emerald-900 bg-black overflow-x-auto w-full") do
            table(role: "table", class: "w-full text-left font-mono text-compact") do
              thead(class: "bg-emerald-950/20 text-emerald-800 uppercase text-mini tracking-widest") do
                tr do
                  th(scope: "col", class: "p-4") { "ID / Status" }
                  th(scope: "col", class: "p-4") { "Organization" }
                  th(scope: "col", class: "p-4") { "Target Cluster" }
                  th(scope: "col", class: "p-4") { "Investment" }
                  th(scope: "col", class: "p-4") { "Current Yield" }
                  th(scope: "col", class: "p-4") { "Period" }
                  th(scope: "col", class: "p-4") { "Performance" }
                  th(scope: "col", class: "p-4 text-right") { "Command" }
                end
              end
              tbody(class: "divide-y divide-emerald-900/30") do
                @contracts.each { |contract| render_contract_row(contract) }
              end
            end
          end

          render Views::Shared::UI::Pagination.new(
            pagy: @pagy,
            url_helper: ->(page:) { api_v1_contracts_path(page: page) }
          )
        end
      end
    end

    private

    def render_stats_hero
      div(class: "grid grid-cols-1 md:grid-cols-3 gap-6") do
        render Views::Shared::UI::StatCard.new(label: "Portfolio Capital", value: "#{@stats[:total_invested].to_f.round(2)} SCC", sub: "Total Injected")
        render Views::Shared::UI::StatCard.new(label: "Biogenic Yield", value: "#{@stats[:total_minted].to_f.round(2)} SCC", sub: "Total Minted")
        render Views::Shared::UI::StatCard.new(label: "Network Health", value: "#{@stats[:avg_health]}%", sub: "Portfolio Avg")
      end
    end

    def render_contract_row(contract)
      tr(class: "hover:bg-emerald-950/10 transition-colors group") do
        td(class: "p-4") do
          div(class: "flex flex-col") do
            span(class: "text-emerald-100") { "##{contract.id}" }
            span(class: tokens("text-mini uppercase mt-1", status_color(contract.status))) { contract.status }
          end
        end
        td(class: "p-4 text-gaia-text-muted") { contract.organization&.name || "—" }
        td(class: "p-4 text-gaia-primary") { contract.cluster&.name || "UNASSIGNED" }
        td(class: "p-4 text-gaia-text-muted") { "#{contract.total_value} SCC" }
        td(class: "p-4 text-gaia-text") { "#{contract.emitted_tokens} SCC" }
        td(class: "p-4 text-tiny text-gaia-text-muted") do
          plain contract.start_date&.strftime("%d.%m.%y")
          plain " → "
          plain contract.end_date&.strftime("%d.%m.%y")
        end
        td(class: "p-4") do
          render_performance_gauge(contract.current_yield_performance)
        end
        td(class: "p-4 text-right") do
          a(href: api_v1_contract_path(contract), class: "text-emerald-600 hover:text-white transition-all focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-emerald-500", aria_label: "View contract ##{contract.id} details") { "AUDIT_DETAILS →" }
        end
      end
    end

    def render_performance_gauge(performance)
      div(class: "flex items-center gap-3") do
        div(class: "w-20 h-1 bg-emerald-950 rounded-full overflow-hidden") do
          div(class: "h-full bg-emerald-500 shadow-[0_0_8px_#10b981]", style: "width: #{performance}%")
        end
        span(class: "text-tiny text-emerald-500 font-mono") { "#{performance.to_i}%" }
      end
    end

    def status_color(status)
      case status
      when "active" then "text-emerald-500"
      when "fulfilled" then "text-blue-400"
      when "breached" then "text-red-500"
      when "cancelled" then "text-gray-500 line-through"
      else "text-status-warning-text"
      end
    end
  end
end
