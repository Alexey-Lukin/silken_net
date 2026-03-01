# frozen_string_literal: true

module Views
  module Components
    module Gateways
      class Item < ApplicationComponent
        def initialize(gateway:)
          @gateway = gateway
          @latest_log = @gateway.gateway_telemetry_logs.order(created_at: :desc).first
        end

        def view_template
          div(class: "group relative p-6 border border-emerald-900 bg-black hover:bg-emerald-950 transition-all duration-500") do
            header_section
            stats_section
            footer_section
          end
        end

        private

        def header_section
          div(class: "flex justify-between items-start mb-6") do
            div do
              h3(class: "text-lg font-light tracking-widest text-emerald-400 uppercase") { "Queen // #{@gateway.uid}" }
              p(class: "text-[10px] font-mono text-emerald-800") { "Cluster: #{@gateway.cluster.name}" }
            end
            
            # Живий індикатор зв'язку
            div(class: tokens(
              "h-2 w-2 rounded-full",
              connection_led_class
            ))
          end
        end

        def stats_section
          div(class: "grid grid-cols-2 gap-4 mb-6") do
            stat_block("Soldiers", @gateway.trees.count)
            stat_block("Signal", "#{@latest_log&.signal_quality_percentage || 0}%")
          end
        end

        def stat_block(label, value)
          div do
            p(class: "text-[9px] uppercase tracking-tighter text-gray-600") { label }
            p(class: "text-xl font-light text-emerald-100") { value }
          end
        end

        def footer_section
          div(class: "flex justify-between items-center mt-4 pt-4 border-t border-emerald-900/50") do
            p(class: "text-[9px] font-mono text-gray-600") { @gateway.last_seen_at&.strftime("%H:%M // %d.%m") || "SILENT" }
            a(
              href: helpers.api_v1_gateway_path(@gateway),
              class: "text-[10px] uppercase tracking-widest text-emerald-600 hover:text-emerald-300 transition-colors"
            ) { "Open Relay →" }
          end
        end

        def connection_led_class
           @gateway.last_seen_at&. > 5.minutes.ago ? "bg-emerald-500 shadow-[0_0_8px_#10b981]" : "bg-red-900 animate-pulse"
        end
      end
    end
  end
end
