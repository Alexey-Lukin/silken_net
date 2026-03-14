# frozen_string_literal: true

module Gateways
  class Index < ApplicationComponent
    def initialize(gateways:, pagy:, online_count: 0)
      @gateways = gateways
      @pagy = pagy
      @online_count = online_count
    end

    def view_template
      div(class: "space-y-8 animate-in fade-in duration-700") do
        render_header

        div(class: "grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6") do
          @gateways.each do |gateway|
            render_gateway_item(gateway)
          end
        end

        render Views::Shared::UI::Pagination.new(
          pagy: @pagy,
          url_helper: ->(page:) { api_v1_gateways_path(page: page) }
        )
      end
    end

    private

    def render_header
      div(class: "flex justify-between items-end mb-6") do
        div do
          h3(class: "text-tiny uppercase tracking-[0.4em] text-emerald-700") { "Queen Registry // Global Relays" }
          p(class: "text-xs text-gray-600 mt-1") { "Monitoring neural synapses of the forest network." }
        end

        div(class: "text-right font-mono text-tiny text-emerald-900") do
          plain "Nodes Online: "
          span(class: "text-emerald-500") { "#{@online_count} / #{@pagy.count}" }
        end
      end
    end

    def render_gateway_item(gateway)
      latest_log = gateway.latest_gateway_telemetry_log
      recently_seen = gateway.last_seen_at&.after?(5.minutes.ago)
      led_class = tokens("bg-emerald-500 shadow-[0_0_8px_#10b981]": recently_seen, "bg-red-900 animate-pulse": !recently_seen)

      div(class: "group relative p-6 border border-emerald-900 bg-black hover:bg-emerald-950 transition-all duration-500") do
        div(class: "flex justify-between items-start mb-6") do
          div do
            h3(class: "text-lg font-light tracking-widest text-emerald-400 uppercase") { "Queen // #{gateway.uid}" }
            p(class: "text-tiny font-mono text-emerald-800") { "Cluster: #{gateway.cluster&.name || 'UNASSIGNED'}" }
          end
          div(class: tokens("h-2 w-2 rounded-full", led_class))
        end

        div(class: "grid grid-cols-2 gap-4 mb-6") do
          div do
            p(class: "text-mini uppercase tracking-tighter text-gray-600") { "Soldiers" }
            p(class: "text-xl font-light text-emerald-100") { gateway.cluster&.active_trees_count || 0 }
          end
          div do
            p(class: "text-mini uppercase tracking-tighter text-gray-600") { "Signal" }
            p(class: "text-xl font-light text-emerald-100") { "#{latest_log&.signal_quality_percentage || 0}%" }
          end
        end

        div(class: "flex justify-between items-center mt-4 pt-4 border-t border-emerald-900/50") do
          p(class: "text-mini font-mono text-gray-600") { gateway.last_seen_at&.strftime("%H:%M // %d.%m") || "SILENT" }
          a(
            href: api_v1_gateway_path(gateway),
            aria_label: "Open gateway #{gateway.uid} details",
            class: "text-tiny uppercase tracking-widest text-emerald-600 hover:text-emerald-300 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-emerald-500 transition-colors"
          ) { "Open Relay →" }
        end
      end
    end
  end
end
