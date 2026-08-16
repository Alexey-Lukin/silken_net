# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Gateways
  class Index < ApplicationComponent
    def initialize(gateways:, pagy:, online_count: 0)
      @gateways = gateways
      @pagy = pagy
      @online_count = online_count
    end

    def view_template
      div(class: "space-y-8") do
        render_header

        div(class: "grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6") do
          @gateways.each do |gateway|
            render_gateway_item(gateway)
          end
        end

        render Views::Shared::UI::Pagination.new(
          pagy: @pagy,
          url_helper: ->(page:) { gateways_path(page: page) }
        )
      end
    end

    private

    def render_header
      div(class: "flex justify-between items-end mb-6") do
        div do
          p(class: "text-xs text-gray-600 mt-1") { t(".subtitle") }
        end

        div(class: "text-right font-mono text-tiny text-emerald-900") do
          plain "#{t('.nodes_online')} "
          span(class: "text-emerald-500") { "#{@online_count} / #{@pagy.count}" }
        end
      end
    end

    def render_gateway_item(gateway)
      latest_log = gateway.latest_gateway_telemetry_log
      recently_seen = gateway.online?
      led_class = tokens("bg-emerald-500 shadow-[0_0_8px_#10b981]": recently_seen, "bg-red-900 animate-pulse": !recently_seen)

      div(class: "group relative p-6 border border-emerald-900 bg-black hover:bg-emerald-950 transition-all duration-500") do
        div(class: "flex justify-between items-start mb-6") do
          div do
            h3(class: "text-lg font-light tracking-widest text-emerald-400 uppercase") { t("gateways.item.label", uid: gateway.uid) }
            p(class: "text-tiny font-mono text-emerald-800") { t("gateways.item.cluster", name: gateway.cluster&.name || t("gateways.item.unassigned")) }
          end
          div(class: tokens("h-2 w-2 rounded-full", led_class))
        end

        div(class: "grid grid-cols-2 gap-4 mb-6") do
          div do
            p(class: "text-mini uppercase tracking-tighter text-gray-600") { t("gateways.item.soldiers") }
            p(class: "text-xl font-light text-emerald-100") { gateway.cluster&.active_trees_count || 0 }
          end
          div do
            p(class: "text-mini uppercase tracking-tighter text-gray-600") { t("gateways.item.signal") }
            # [ARCH.84] CSQ=99 («unknown» за 3GPP) більше не друкується як 0% — модель
            # віддає `nil`, і тут це стан, а не число.
            p(class: "text-xl font-light text-emerald-100") do
              measured_value(latest_log&.signal_quality_percentage, "%", space: false)
            end
          end
        end

        div(class: "flex justify-between items-center mt-4 pt-4 border-t border-emerald-900/50") do
          p(class: "text-mini font-mono text-gray-600") { gateway.last_seen_at&.strftime("%H:%M // %d.%m") || t("gateways.item.silent") }
          a(
            href: gateway_path(gateway),
            aria_label: t("gateways.item.open_aria", uid: gateway.uid),
            class: "text-tiny uppercase tracking-widest text-emerald-600 hover:text-emerald-300 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-emerald-500 transition-colors"
          ) { t("gateways.item.open") }
        end
      end
    end
  end
end
