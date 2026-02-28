# app/views/components/firmwares/index.rb
# frozen_string_literal: true

module Views
  module Components
    module Firmwares
      class Index < ApplicationComponent
        def initialize(firmwares:, inventory_stats:)
          @firmwares = firmwares
          @inventory_stats = inventory_stats
        end

        def view_template
          div(class: "space-y-10 animate-in fade-in duration-700") do
            render_inventory_summary
            render_firmware_registry
          end
        end

        private

        def render_inventory_summary
          div(class: "p-6 border border-emerald-900 bg-zinc-950") do
            h3(class: "text-[10px] uppercase tracking-[0.4em] text-emerald-700 mb-6") { "Forest Inventory (Version Distribution)" }
            
            div(class: "grid grid-cols-1 md:grid-cols-2 gap-8") do
              inventory_block("Queens (Gateways)", @inventory_stats[:gateways])
              inventory_block("Soldiers (Trees)", @inventory_stats[:trees])
            end
          end
        end

        def inventory_block(title, stats)
          div do
            p(class: "text-xs font-mono text-gray-500 mb-3") { title }
            div(class: "space-y-2") do
              stats.each do |version, count|
                div(class: "flex justify-between items-center text-[11px] font-mono") do
                  span(class: "text-emerald-400") { "v#{version}" }
                  div(class: "flex-1 mx-4 h-px bg-emerald-900/30")
                  span(class: "text-emerald-100") { "#{count} units" }
                end
              end
            end
          end
        end

        def render_firmware_registry
          div(class: "space-y-4") do
            div(class: "flex justify-between items-end") do
              h3(class: "text-[10px] uppercase tracking-widest text-emerald-700") { "Available Binary Evolutions" }
              # Кнопка для завантаження (можна додати модалку пізніше)
              button(class: "text-[10px] border border-emerald-800 px-3 py-1 text-emerald-600 hover:bg-emerald-900 hover:text-white transition-all uppercase") { "+ Upload New Code" }
            end

            div(class: "overflow-x-auto border border-emerald-900") do
              table(class: "w-full text-left font-mono text-xs") do
                thead(class: "bg-emerald-950/20 text-emerald-800 uppercase text-[9px] tracking-widest") do
                  tr do
                    th(class: "p-4") { "Version" }
                    th(class: "p-4") { "Target Hardware" }
                    th(class: "p-4") { "Checksum" }
                    th(class: "p-4") { "Uploaded" }
                    th(class: "p-4 text-right") { "Action" }
                  end
                end
                tbody(class: "divide-y divide-emerald-900/30") do
                  @firmwares.each { |f| render Views::Components::Firmwares::Row.new(firmware: f) }
                end
              end
            end
          end
        end
      end
    end
  end
end
