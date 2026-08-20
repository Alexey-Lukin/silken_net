# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Gateways
  class Index < ApplicationComponent
    # [PERF.1 (а)] `latest_logs` — хеш `queen_uid → останній пульс`, який будує
    # контролер (`GatewayTelemetryLog.latest_per_gateway`). Доти компонент читав
    # `gateway.latest_gateway_telemetry_log`, тобто асоціацію, і був справним лише
    # доки викликач не забув її преload'ити — а преload заради одного рядка на
    # шлюз і був самим дефектом.
    #
    # ⚠️ Kwarg БЕЗ дефолту свідомо: `latest_logs: {}` перетворив би забуту проводку
    # на «весь флот без телеметрії» — правдоподібний екран, якого ніхто не
    # прочитає як поломку. Гучний `ArgumentError` тут чесніший за тихий порожній
    # стан (клас «мовчазний дефолт»).
    def initialize(gateways:, pagy:, latest_logs:, online_count: 0)
      @gateways = gateways
      @pagy = pagy
      @latest_logs = latest_logs
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
          p(class: "text-xs text-gaia-text-muted mt-1") { t(".subtitle") }
        end

        div(class: "text-right font-mono text-tiny text-gaia-text-subtle") do
          plain "#{t('.nodes_online')} "
          span(class: "text-gaia-primary-strong") { "#{@online_count} / #{@pagy.count}" }
        end
      end
    end

    def render_gateway_item(gateway)
      latest_log = @latest_logs[gateway.uid]
      recently_seen = gateway.online?
      led_class = tokens("bg-emerald-500 shadow-[0_0_8px_#10b981]": recently_seen, "bg-red-900 animate-pulse": !recently_seen)

      div(class: "group relative p-6 border border-gaia-border bg-gaia-surface hover:bg-gaia-surface-sunken transition-all duration-500") do
        div(class: "flex justify-between items-start mb-6") do
          div do
            h3(class: "text-lg font-light tracking-widest text-gaia-text-strong uppercase") { t("gateways.item.label", uid: gateway.uid) }
            p(class: "text-tiny font-mono text-gaia-text-subtle") { t("gateways.item.cluster", name: gateway.cluster&.name || t("gateways.item.unassigned")) }
          end
          div(class: tokens("h-2 w-2 rounded-full", led_class))
        end

        div(class: "grid grid-cols-2 gap-4 mb-6") do
          div do
            p(class: "text-mini uppercase tracking-tighter text-gaia-text-muted") { t("gateways.item.soldiers") }
            # [ARCH.84] Нуль тут — ЗАКОННИЙ вимір (порожній кластер), тож `|| 0`
            # робив шлюз без кластера невідрізнимим від шлюза з порожнім. Чесна
            # відповідь стоїть рядком ВИЩЕ (`unassigned`), і питання «скільки
            # солдатів у кластері» для безкластерного шлюза просто не існує —
            # тому тире, а не «не виміряно» (`ApplicationComponent#measured_value`).
            p(class: "text-xl font-light text-gaia-text-strong") do
              gateway.cluster ? gateway.cluster.active_trees_count : "—"
            end
          end
          div do
            p(class: "text-mini uppercase tracking-tighter text-gaia-text-muted") { t("gateways.item.signal") }
            # [ARCH.84] CSQ=99 («unknown» за 3GPP) більше не друкується як 0% — модель
            # віддає `nil`, і тут це стан, а не число.
            p(class: "text-xl font-light text-gaia-text-strong") do
              measured_value(latest_log&.signal_quality_percentage, "%", space: false)
            end
          end
        end

        div(class: "flex justify-between items-center mt-4 pt-4 border-t border-gaia-border-strong") do
          p(class: "text-mini font-mono text-gaia-text-muted") { gateway.last_seen_at&.strftime("%H:%M // %d.%m") || t("gateways.item.silent") }
          a(
            href: gateway_path(gateway),
            aria_label: t("gateways.item.open_aria", uid: gateway.uid),
            class: "text-tiny uppercase tracking-widest text-gaia-primary-strong hover:text-gaia-text-strong focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary-strong transition-colors"
          ) { t("gateways.item.open") }
        end
      end
    end
  end
end
