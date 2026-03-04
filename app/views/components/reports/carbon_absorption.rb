# frozen_string_literal: true

module Views
  module Components
    module Reports
      class CarbonAbsorption < ApplicationComponent
        def initialize(organization:, data:)
          @organization = organization
          @data = data
        end

        def view_template
          div(class: "space-y-8 animate-in fade-in duration-500") do
            header_section
            render_metrics
            render_data_table
            render_footer
          end
        end

        private

        def header_section
          div(class: "p-8 border border-emerald-900 bg-black shadow-2xl relative overflow-hidden") do
            div(class: "absolute top-0 right-0 p-4 text-[60px] font-bold text-emerald-900/5 select-none") { "CO₂" }
            div do
              p(class: "text-[10px] uppercase tracking-[0.4em] text-emerald-700 mb-2") { "🌿 Carbon Absorption Report" }
              h2(class: "text-3xl font-extralight tracking-tighter text-white") { @organization.name }
              p(class: "text-[10px] font-mono text-gray-600 mt-2") { "Generated: #{Time.current.strftime('%d.%m.%Y %H:%M UTC')}" }
            end
          end
        end

        def render_metrics
          div(class: "grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6") do
            stat_card("Total Carbon Points", @data[:total_carbon_points], "SCC")
            stat_card("Active Wallets", @data[:wallets_count], "Wallets")
            stat_card("Active Trees", @data[:trees_active], "Online")
            stat_card("Total Trees", @data[:trees_total], "Deployed")
          end
        end

        def stat_card(label, value, sub)
          div(class: "p-6 border border-emerald-900 bg-zinc-950") do
            p(class: "text-[10px] uppercase tracking-widest text-emerald-700 mb-4") { label }
            div(class: "flex items-baseline space-x-2") do
              span(class: "text-3xl font-light text-white") { value.to_s }
              span(class: "text-[10px] text-gray-600 font-mono") { sub }
            end
          end
        end

        def render_data_table
          div(class: "border border-emerald-900 bg-black overflow-hidden") do
            table(class: "w-full text-left font-mono text-[11px]") do
              thead(class: "bg-emerald-950/20 text-emerald-800 uppercase text-[9px] tracking-widest") do
                tr do
                  th(class: "p-4") { "Metric" }
                  th(class: "p-4 text-right") { "Value" }
                end
              end
              tbody(class: "divide-y divide-emerald-900/30") do
                data_row("Total Carbon Points Accumulated", @data[:total_carbon_points])
                data_row("Active Wallets Generating Points", @data[:wallets_count])
                data_row("Trees Currently Online", @data[:trees_active])
                data_row("Trees Deployed (All Statuses)", @data[:trees_total])
              end
            end
          end
        end

        def data_row(label, value)
          tr(class: "hover:bg-emerald-950/10") do
            td(class: "p-4 text-emerald-500") { label }
            td(class: "p-4 text-right text-gray-300") { value.to_s }
          end
        end

        def render_footer
          div(class: "text-[9px] text-gray-600 text-right mt-2 font-mono") do
            "Report generated at #{Time.current.strftime('%Y-%m-%d %H:%M:%S UTC')} for #{@organization.name}"
          end
        end
      end
    end
  end
end
