# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Contracts
  class Index < ApplicationComponent
    # [ARCH.103] `cluster_emissions:` — kwarg БЕЗ дефолту свідомо: `{}` перетворив би
    # забуту проводку на «увесь портфель із нульовою емісією», тобто на правдоподібний
    # екран, якого ніхто не прочитає як поломку. Прецедент форми той самий, що в
    # `gateways#index` з пульсами шлюзів.
    def initialize(contracts:, stats:, pagy:, cluster_emissions:)
      @contracts = contracts
      @stats = stats
      @pagy = pagy
      @cluster_emissions = cluster_emissions
    end

    def view_template
      div(class: "space-y-8") do
        render_stats_hero

        div(class: "space-y-4") do
          h3(class: "text-tiny uppercase tracking-[0.4em] text-emerald-700") { t(".portfolio_title") }

          div(class: "border border-emerald-900 bg-black overflow-x-auto w-full") do
            table(role: "table", class: "w-full text-left font-mono text-compact") do
              thead(class: "bg-emerald-950/20 text-emerald-800 uppercase text-mini tracking-widest") do
                tr do
                  th(scope: "col", class: "p-4") { t(".columns.id_status") }
                  th(scope: "col", class: "p-4") { t(".columns.organization") }
                  th(scope: "col", class: "p-4") { t(".columns.target_cluster") }
                  th(scope: "col", class: "p-4") { t(".columns.investment") }
                  th(scope: "col", class: "p-4") { t(".columns.cluster_emission") }
                  th(scope: "col", class: "p-4") { t(".columns.period") }
                  # [UI.10] Колонки «Cluster Health» тут більше немає: датчик під
                  # цим підписом малював `current_yield_performance` — SCC/USD, —
                  # тобто чужу величину. Здоровʼя кластера має два чесні доми:
                  # агрегат у герої вище й `backing_asset` у `contracts#show`.
                  th(scope: "col", class: "p-4 text-right") { t(".columns.command") }
                end
              end
              tbody(class: "divide-y divide-emerald-900/30") do
                @contracts.each { |contract| render_contract_row(contract) }
              end
            end
          end

          render Views::Shared::UI::Pagination.new(
            pagy: @pagy,
            url_helper: ->(page:) { contracts_path(page: page) }
          )
        end
      end
    end

    private

    def render_stats_hero
      div(class: "grid grid-cols-1 md:grid-cols-3 gap-6") do
        # Одиниця тут USD, а не SCC: `total_contracted` агрегує `naas_contracts.total_value`
        # (alias на `total_funding`) — «сума оплати за послугу (USDC/USD)» за 07_01 §5, і вся
        # юніт-економіка 07_01 §11-§20 рахує в $. Сусідня картка нижче правомірно в SCC —
        # там справді емісія. Дві різні валюти на одній сітці, тож не «уніфікуй» їх.
        render Views::Shared::UI::StatCard.new(label: t(".stats.portfolio_capital"), value: "#{formatted_amount(@stats[:total_contracted])} USD", sub: t(".stats.total_injected"))
        render Views::Shared::UI::StatCard.new(label: t(".stats.net_cluster_emission"), value: "#{formatted_amount(@stats[:total_minted])} SCC", sub: t(".stats.total_minted"))
        render Views::Shared::UI::StatCard.new(label: t(".stats.network_health"),
                                               value: measured_percent(@stats[:cluster_health].average, precision: 1),
                                               sub: network_health_sub)
      end
    end

    # Контролер кладе `cluster_health` — те саме ім'я, що в `show` і `stats`; доти тут
    # читалось `avg_health`, якого не існує, тож картка рендерила голе «%».
    # Шкала джерела — 0..1 (`health_index`), у відсоток переводить в'ю: «%» — форма
    # подачі, а не одиниця даних.
    # [ARCH.84] Підпис картки каже «Avg Cluster Health», і саме він вирішив, ЯК рахувати
    # (по кластерах, не по рядках контрактів — `contracts_controller`). Коли покриття
    # неповне, підпис поступається місцем підставі: без неї середнє по одному кластеру
    # читалось би як твердження про весь портфель.
    def network_health_sub
      measurement_coverage(@stats[:cluster_health].measured, @stats[:cluster_health].total) ||
        t(".stats.portfolio_avg")
    end

    def render_contract_row(contract)
      tr(class: "hover:bg-emerald-950/10 transition-colors group") do
        td(class: "p-4") do
          div(class: "flex flex-col") do
            span(class: "text-emerald-100") { "##{contract.id}" }
            div(class: "mt-1") { render Views::Shared::UI::StatusBadge.new(status: contract.status) }
          end
        end
        td(class: "p-4 text-gaia-text-muted") { contract.organization&.name || "—" }
        td(class: "p-4 text-gaia-primary-strong") { contract.cluster&.name || t(".unassigned") }
        # `total_value` = alias на `total_funding` (плата за послугу, USD) ⊥ сусідня
        # комірка — чиста емісія КЛАСТЕРА в SCC. Дві сусідні комірки в РІЗНИХ валютах
        # і про РІЗНІ субʼєкти (контракт ⊥ кластер) — це не дрейф, а наслідок ARCH.103.
        td(class: "p-4 text-gaia-text-muted") { "#{contract.total_value} USD" }
        # 🔴 [ARCH.103] Тут ДВА різні стани, і зливати їх не можна. Контракт БЕЗ кластера —
        # питання без субʼєкта, тобто чесне «не виміряно». Кластер, що Є, завжди дає
        # число, і нуль у ньому ВИМІРЯНИЙ (агрегат виконався, підтверджених рухів немає) —
        # тому `fetch(id, 0)`, а не `[id]`: розріджений хеш віддає `nil` саме на таких
        # кластерах, і намалювати там «не виміряно» означало б [`ARCH.84`] навиворіт —
        # приховати вимір замість вигадати його.
        td(class: "p-4 text-gaia-text") do
          plain "#{formatted_amount(@cluster_emissions.fetch(contract.cluster_id, 0))} SCC"
        end
        td(class: "p-4 text-tiny text-gaia-text-muted") do
          plain contract.start_date&.strftime("%d.%m.%y")
          plain " → "
          plain contract.end_date&.strftime("%d.%m.%y")
        end
        td(class: "p-4 text-right") do
          a(href: contract_path(contract), class: "text-emerald-600 hover:text-white transition-all focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary-strong", aria_label: t(".audit_aria", id: contract.id)) { t(".audit_details") }
        end
      end
    end
  end
end
