# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Clusters
  class Show < ApplicationComponent
    # All data must be pre-loaded in the controller — no fallback queries.
    #
    # 🔴 [UI.3] `active_contract` доти діставався ТУТ — `@cluster.active_contract`,
    # тобто запит у Phlex-конструкторі, за пʼять рядків під коментарем, який це
    # прямо забороняє (`CLAUDE.md §6`). Самосуперечність у сусідніх рядках і є
    # причиною, чому дефект прожив: правило стояло, і саме його присутність
    # читалась як виконання.
    #
    # ⚠️ Статичним сканом він невидимий, і це вимір, а не здогад: детектор
    # AR-ланцюжків (`.where` · `.order` · `.first`) у тілах `initialize` дає по
    # дереву **нуль** — бо запит тут ховається за ДОМЕННИМ методом моделі
    # (`Cluster#active_contract` = `naas_contracts.active.order(...).first`), а
    # читання доменного методу синтаксично не відрізнити від читання атрибута.
    # Носій тому рантаймовий — спека рахує SQL під час самого конструювання.
    #
    # @param cluster [Cluster] must respond to :name, :region, :health_index
    # @param gateways [Array<Gateway>] pre-loaded gateways for this cluster
    # @param recent_alerts [Array<EwsAlert>] pre-loaded unresolved alerts
    # @param active_contract [NaasContract, nil] pre-loaded; nil = контракту немає
    # @param health_measured [Integer, nil] скільки живих дерев сектора заговорило за звітну добу
    # @param health_total [Integer, nil] скільки їх усього живих; пара — підстава під `health_index`
    #
    # 🔴 [ARCH.84] Пара покриття БЕЗ дефолту свідомо, і причина та сама, що в
    # `Gateways::Index#latest_logs` (PERF.1): `nil`-дефолт зробив би забуту проводку
    # невідрізнимою від «виміряно повністю» — `measurement_coverage` мовчить в обох
    # випадках, тобто екран читався б як здоровий. Явний `nil` від контролера — це
    # рішення («інсайту за добу немає»), пропущений аргумент — недогляд; тільки
    # обовʼязковий kwarg їх розводить, і робить це гучно.
    # [ARCH.103] `cluster_emission:` без дефолту: величина належить КЛАСТЕРУ сторінки,
    # тож субʼєкт відомий завжди — «не виміряно» тут не виникає в принципі, а забута
    # проводка мусить падати, а не малювати нуль.
    def initialize(cluster:, gateways:, recent_alerts:, health_measured:, health_total:,
                   cluster_emission:, active_contract: nil)
      raise ArgumentError, "cluster must respond to :name" unless cluster.respond_to?(:name)

      @cluster = cluster
      @gateways = gateways
      @active_contract = active_contract
      @cluster_emission = cluster_emission
      @health_measured = health_measured
      @health_total = health_total
      @recent_alerts = recent_alerts
    end

    def view_template
      # ⚡ [СИНХРОНІЗАЦІЯ]: Підписка на потік оновлень алертів кластера
      turbo_stream_from @cluster, :alerts

      div(class: "space-y-8") do
        render_header
        div(class: "grid grid-cols-1 xl:grid-cols-3 gap-8") do
          div(class: "xl:col-span-2 space-y-8") do
            render_vitals_panel
            render_gateways_table
            render_alerts_panel
          end
          div(class: "space-y-8") do
            render_contract_panel
            render_geography_panel
          end
        end
      end
    end

    private

    def render_header
      div(class: "p-8 border border-gaia-border bg-gaia-surface shadow-2xl relative overflow-hidden") do
        div(class: "absolute top-0 right-0 p-4 text-[80px] font-bold text-emerald-900/5 select-none", aria_hidden: "true") { "SECTOR" }
        div(class: "flex justify-between items-start") do
          div do
            p(class: "text-tiny uppercase tracking-[0.4em] text-gaia-text-muted mb-2") { t(".header.eyebrow") }
            h2(class: "text-3xl font-extralight tracking-tighter text-gaia-text-strong") { @cluster.name }
            p(class: "text-tiny font-mono text-gaia-text-muted mt-2") { "#{@cluster.region} // ID: #{@cluster.id}" }
          end
          # Один читок предиката на рендер — він б'є в БД і не мемоїзується (див. `Clusters::Item`).
          threats = @cluster.active_threats?
          div(class: "flex items-center gap-4") do
            div(class: tokens(
              "h-3 w-3 rounded-full",
              "bg-status-danger-accent animate-pulse": threats,
              "bg-gaia-primary-strong": !threats
            ))
            span(class: "text-tiny font-mono text-gaia-text-subtle uppercase") do
              threats ? t(".header.threat_detected") : t(".header.nominal")
            end
          end
        end
      end
    end

    def render_vitals_panel
      div(class: "p-8 border border-gaia-border bg-gaia-surface-sunken") do
        h3(class: "text-tiny uppercase tracking-[0.4em] text-gaia-text-muted mb-8") { t(".vitals.heading") }
        div(class: "grid grid-cols-3 gap-8") do
          # [ARCH.84] Підстава їде під числом: `health_index` = 1 − середнє стресу по
          # деревах, що заговорили, тож без покриття «100%» на лісі, виміряному на
          # пʼяту частину, невідрізнимі від повного. `measurement_coverage` мовчить на
          # повному покритті — рядок зʼявляється рівно тоді, коли щось означає.
          vital_block(t(".vitals.health_index"), measured_percent(@cluster.health_index),
                      sub: measurement_coverage(@health_measured, @health_total))
          vital_block(t(".vitals.active_trees"), @cluster.total_active_trees.to_s)
          vital_block(t(".vitals.queen_gateways"), @gateways.size.to_s)
        end
        if @cluster.environmental_settings.present?
          div(class: "mt-8 pt-6 border-t border-gaia-border") do
            h4(class: "text-mini uppercase tracking-widest text-gaia-text-subtle mb-4") { t(".vitals.env_config") }
            div(class: "grid grid-cols-3 gap-6 text-tiny font-mono") do
              if @cluster.environmental_settings["custom_fire_threshold"]
                env_block(t(".vitals.fire_threshold"), "#{@cluster.environmental_settings['custom_fire_threshold']}°C")
              end
              if @cluster.environmental_settings["seismic_sensitivity_threshold"]
                env_block(t(".vitals.seismic_sensitivity"), @cluster.environmental_settings["seismic_sensitivity_threshold"].to_s)
              end
              if @cluster.environmental_settings["timezone"]
                env_block(t(".vitals.timezone"), @cluster.environmental_settings["timezone"])
              end
            end
          end
        end
      end
    end

    def vital_block(label, value, sub: nil)
      div do
        p(class: "text-mini uppercase tracking-tighter text-gaia-text-muted") { label }
        p(class: "text-3xl font-extralight text-gaia-text-strong") { value }
        p(class: "text-micro text-status-warning-text font-mono mt-1") { sub } if sub
      end
    end

    def env_block(label, value)
      div do
        p(class: "text-gaia-text-muted uppercase") { label }
        p(class: "text-gaia-primary-strong mt-1") { value }
      end
    end

    def render_gateways_table
      div(class: "border border-gaia-border bg-gaia-surface overflow-x-auto w-full") do
        h3(class: "p-4 text-tiny uppercase tracking-widest text-gaia-text-muted border-b border-gaia-border") { t(".gateways.heading") }
        table(role: "table", class: "w-full text-left font-mono text-tiny") do
          thead(class: "bg-gaia-surface-sunken text-gaia-text-subtle uppercase text-micro tracking-widest") do
            tr do
              th(scope: "col", class: "p-4") { t(".gateways.uid") }
              th(scope: "col", class: "p-4") { t(".gateways.state") }
              th(scope: "col", class: "p-4") { t(".gateways.coordinates") }
              th(scope: "col", class: "p-4 text-right") { t(".gateways.last_seen") }
            end
          end
          tbody(class: "divide-y divide-gaia-border") do
            if @gateways.any?
              @gateways.each { |gw| render_gateway_row(gw) }
            else
              tr { td(colspan: 4, class: "p-10 text-center text-gaia-text-subtle uppercase tracking-widest") { t(".gateways.empty") } }
            end
          end
        end
      end
    end

    def render_gateway_row(gw)
      tr(class: "hover:bg-gaia-surface-sunken transition-colors") do
        td(class: "p-4 text-gaia-text") { gw.uid }
        td(class: "p-4") { render Views::Shared::UI::StatusBadge.new(status: gw.state) }
        td(class: "p-4 text-gaia-text-muted") { "#{gw.latitude}, #{gw.longitude}" }
        td(class: "p-4 text-right text-gaia-text-muted") { gw.last_seen_at&.strftime("%H:%M:%S // %d.%m.%y") || "—" }
      end
    end

    def render_alerts_panel
      div(class: "p-6 border border-gaia-border bg-gaia-surface") do
        h3(class: "text-tiny uppercase tracking-widest text-gaia-text-muted mb-4") { t(".alerts.heading") }
        # ⚡ [СИНХРОНІЗАЦІЯ]: alerts_list — ВЛАСНИЙ якір списку цієї сторінки, а
        # НЕ приймач броадкасту. Обидва продюсери `EwsAlert` шлють сигнал
        # (`broadcast_refresh_later_to`), тож сторінка переграє власний запит і
        # сама вирішує форму та дієслово — `04_04 §8.1б`.
        div(id: "alerts_list", class: "space-y-2") do
          if @recent_alerts.any?
            @recent_alerts.each do |alert|
              div(id: dom_id(alert), class: "flex justify-between items-center py-2 border-b border-gaia-border font-mono text-tiny") do
                div(class: "flex items-center gap-3") do
                  div(class: tokens("h-2 w-2 rounded-full", alert_severity_class(alert)))
                  # Через TextFormatter, як `Alerts::Row` — інакше тут жила б
                  # друга деривація тієї самої мітки (див. `04_04 §12.14`).
                  span(class: "text-gaia-text uppercase") { TreeChronicle::TextFormatter.alert_title(alert) }
                end
                span(class: "text-gaia-text-muted") { alert.created_at.strftime("%d.%m.%y %H:%M") }
              end
            end
          else
            p(class: "text-compact text-gaia-text italic") { t(".alerts.nominal") }
          end
        end
      end
    end

    def render_contract_panel
      div(class: "p-6 border border-gaia-border bg-gaia-surface-sunken") do
        h3(class: "text-tiny uppercase tracking-widest text-gaia-text-muted mb-4") { t(".contract.heading") }
        if @active_contract
          div(class: "space-y-3 font-mono text-tiny") do
            contract_row(t(".contract.status"), Views::Shared::UI::StatusBadge.label(@active_contract.status).upcase)
            # 🔴 Одиниця тут USD, а не SCC, і сусідство це приховувало: рядок нижче
            # правомірно каже «Emitted SCC», а цей стояв БЕЗ одиниці взагалі, тож
            # читався в тій самій валюті. `total_value` — alias на `total_funding`,
            # тобто плата клієнта за послугу (`00_04 §5`) — той самий клас, що [I18N.1]
            # закрив на семи сайтах; цей був восьмим. Формат — як у `contracts/index`:
            # гроші друкуються з копійками, бо `numeric` через голий `to_s` дає «50000.0».
            contract_row(t(".contract.value"), "#{formatted_amount(@active_contract.total_value)} USD")
            # ✅ [ARCH.103] ⚖️ Кластерна семантика: рядок друкує емісію САМОГО кластера
            # цієї сторінки, а не приписану контрактові. `measured_value` лишається,
            # але спрацювати на `nil` тут уже не може — субʼєкт відомий завжди, і нуль
            # є виміром. Мітка називає кластер явно, інакше це була б інша множина під
            # старим підписом.
            # ⚠️ Формат ділить дім із USD-рядком вище (`formatted_amount`), і це не стиль:
            # `measured_value` інтерполює сирий BigDecimal, а `amount` це `numeric(24,6)` —
            # той самий кластер друкувався б тут із шістьма знаками, а на `contracts/*` із
            # двома. `measured_value` заразом і зайвий: субʼєкт тут гарантований.
            contract_row(t(".contract.cluster_emission"), "#{formatted_amount(@cluster_emission)} SCC")
          end
        else
          p(class: "text-compact text-gaia-text italic") { t(".contract.empty") }
        end
      end
    end

    def contract_row(label, value)
      div(class: "flex justify-between items-center") do
        span(class: "text-gaia-text-muted uppercase") { label }
        span(class: "text-gaia-text") { value }
      end
    end

    def render_geography_panel
      center = @cluster.geo_center
      div(class: "p-6 border border-gaia-border bg-gaia-surface space-y-4") do
        h3(class: "text-tiny uppercase tracking-widest text-gaia-text-muted") { t(".geography.heading") }
        div(class: "space-y-3 text-tiny font-mono") do
          geo_row(t(".geography.region"), @cluster.region)
          geo_row(t(".geography.mapped"), @cluster.mapped? ? t(".geography.mapped_yes") : t(".geography.mapped_no"))
          if center
            geo_row(t(".geography.centroid"), "#{center[:lat].round(4)}, #{center[:lng].round(4)}")
            a(
              href: "https://www.google.com/maps?q=#{center[:lat]},#{center[:lng]}",
              target: "_blank",
              class: "block mt-4 text-center p-2 border border-gaia-border-strong text-gaia-primary-strong hover:bg-gaia-surface-sunken hover:text-gaia-text-strong transition-all uppercase focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary-strong",
              aria_label: t(".map_link_aria")
            ) { t(".geography.view_on_map") }
          end
        end
      end
    end

    def geo_row(label, value)
      div(class: "flex justify-between") do
        span(class: "text-gaia-text-muted") { "#{label}:" }
        span(class: "text-gaia-text") { value }
      end
    end

    # Точка тяжкості. Спільним із бейджем `Alerts::Row` є не рядок класів
    # (крапці потрібен лише фон, бейджу — ще й колір тексту), а СЕМАНТИКА:
    # та сама тяжкість мусить читатись тим самим рівнем на обох поверхнях.
    # `low` тут був `bg-emerald-500` — зелений «усе гаразд», тоді як у рядку
    # та сама тривога синя; `else` дублював ту саму зелень для значення,
    # якого enum не має, тобто ховав би майбутнє поповнення в «усе гаразд».
    # [UI.1 сигнальна хвиля] Крапка — СИГНАЛ (1.4.11 ≥ 3:1), тож кожен рівень іде
    # насиченим `-accent`-двійником, ніколи пастельним фоном бейджа: `bg-status-warning`
    # у ролі крапки давав 1.17:1 у світлій. `else` лишається пастельним свідомо —
    # це гард на значення поза enum'ом, не штатний стан.
    def alert_severity_class(alert)
      case alert.severity.to_s
      when "critical" then "bg-status-danger-accent animate-pulse"
      when "medium" then "bg-status-warning-accent"
      when "low" then "bg-status-info-accent"
      else "bg-status-neutral"
      end
    end
  end
end
