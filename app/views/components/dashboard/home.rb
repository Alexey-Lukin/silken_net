# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Dashboard
  class Home < ApplicationComponent
    # 🔴 [UI.4] `map_total` БЕЗ дефолту свідомо: `nil` зробив би забуту проводку
    # невідрізнимою від «стеля не досягнута» — `measurement_coverage` мовчить в обох
    # випадках, тож екран читався б як здоровий. Той самий вибір, що
    # `Gateways::Index#latest_logs` (PERF.1) і `Clusters::Show#health_measured` (ARCH.84).

    # [UI.4] Домени, з яких зібрана стрічка подій (`Api::V1::DashboardController#fetch_recent_events`).
    #
    # 🔴 Чому підписка на ДОМЕНИ, а не на власний стрім сторінки. Стрічка — похідний
    # міжсутнісний рейтинг (три запити по 3 → злиття → сорт → зріз 8), тож жоден
    # фрагмент її не виражає, і єдина легальна форма живості тут — сторінковий
    # сигнал (`04_04 §8.1б`). Спокуса була зробити `org(:dashboard)` і слати туди з
    # трьох моделей; це розвернуло б залежність не в той бік — модель почала б
    # перелічувати СТОРІНКИ, і четвертий екран із тривогами знову вимагав би правити
    # `EwsAlert`. Двоє з трьох продюсерів УЖЕ шлють org-сигнал свого домену
    # (`broadcast_org_refresh` · `broadcast_ledger_signal`); третій дописаний за їхнім
    # зразком. Отже: сигнал — на домен, підписка — на сторінку.
    #
    # ⚠️ Набір заморожений СВІДОМО й мусить дорівнювати складу `fetch_recent_events`:
    # зайвий домен = зайвий повний GET сторінки на кожну чужу подію, відсутній =
    # мовчазно застаріла стрічка. Пін — рівність множини (`turbo_stream_scope_spec`),
    # бо тут дефект виглядає як ЗАЙВИЙ стрім, а не як відсутній.
    FEED_DOMAINS = %i[alerts ledger maintenance].freeze

    def initialize(stats:, events:, trees:, organization:, map_total:)
      @stats = stats
      @events = events
      @trees = trees
      @organization = organization
      @map_total = map_total
    end

    def view_template
      div(class: "space-y-10") do
        # Без організації підписки нема (fail-closed) — те саме, що `Dashboard::Map`.
        FEED_DOMAINS.each { |kind| turbo_stream_from TurboStreams::Name.org(kind, @organization) } if @organization

        # Ряд головних метрик (The Four Pillars)
        div(class: "grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6") do
          # `health_avg` — середнє `health_index`, шкала 0..1 (`04_01 §3`). Доти тут
          # стояло `.to_i`, тобто 0.92 → **0**: здорова організація бачила «0%»
          # життєздатності на головній сторінці. Переведення у відсоток робить в'ю —
          # так само, як `clusters/show`, `clusters/item`, `organizations/show`,
          # `contracts/show`.
          # [ARCH.84] `.to_f` тут був НЕ форматуванням, а мовчазним дефолтом: на
          # невиміряному фонді він давав «0%» — тобто «ліс мертвий» замість «не міряли»,
          # і жоден тест не червонів, бо `StatCard` робить `to_s` і не кидає ніколи.
          render Views::Shared::UI::StatCard.new(
            label: t(".stats.forest_vitality"),
            value: measured_percent(@stats[:trees][:health_avg]),
            sub: measurement_coverage(@stats[:trees][:clusters_measured], @stats[:trees][:clusters_total])
          )
          render Views::Shared::UI::StatCard.new(label: t(".stats.active_soldiers"), value: @stats[:trees][:active], sub: "/ #{@stats[:trees][:total]}")
          # [ARCH.88] Величина = `org.wallets.sum(:balance)`, тобто БАЛИ росту, а не
          # монети — `sub` був зашитим літералом «SCC» і завищував її в 10 000×.
          # ⚠️ Тут ДВА незалежні носії одиниці (label і sub), і гниють вони окремо.
          render Views::Shared::UI::StatCard.new(label: t(".stats.growth_treasury"), value: @stats[:economy][:total_scc], sub: t(".stats.growth_treasury_sub"))
          # [ARCH.88 фаза 2] Сусідня картка НАВМИСНО в іншій одиниці: бали ⊥ монети.
          # Це не дублювання — це дві різні величини, і саме їх злиття в одну й було
          # дефектом. Розбіжність підписів тут СВІДОМА, «уніфікувати» її не можна.
          render Views::Shared::UI::StatCard.new(label: t(".stats.minted_scc"), value: @stats[:economy][:minted_scc], sub: t(".stats.minted_scc_sub"))
          # 🔴 [ARCH.84/ARCH.99] `danger:` знято 2026-08-14 — це була ДРУГА копія
          # фабрикації, знятої в контролері: та сама «< 3300» на шині VDDA, яку
          # BQ25570 сам і стабілізує на 3.3 В. Червоний тут означав би «мало
          # енергії», а величина про запас енергії не каже нічого за конструкцією.
          # ⊕ Саме тому копія й вижила окремо: `energy.status` контролера мав нуль
          # споживачів, бо в'ю не читало його — воно повторювало обчислення.
          # **Дублікат ховається не там, де One-Home шукають: не другий ВИКЛИК, а
          # другий ВИВІД тієї самої формули.** Число лишається сирим і діагностичним.
          render Views::Shared::UI::StatCard.new(
            label: t(".stats.supply_voltage"),
            # [ARCH.84] `measured_value`, а не інтерполяція: `nil` тут означає, що
            # жодне активне дерево ще не звітувало, і доти це друкувалось «0mV» —
            # найгіршим МОЖЛИВИМ виміром замість відсутності виміру.
            value: measured_value(@stats[:energy][:avg_voltage], "mV", space: false)
          )
        end

        # Центральна секція: Карта та Алерти
        div(class: "grid grid-cols-1 lg:grid-cols-3 gap-8") do
          render_geospatial_matrix
          render_live_feed
        end
      end
    end

    private

    # Обгортка несе ЛИШЕ позицію в сітці: рамку, висоту й фон тримає сам
    # `Dashboard::Map`, інакше вийшла б рамка в рамці й подвійні 500px.
    def render_geospatial_matrix
      div(class: "lg:col-span-2") do
        render Dashboard::Map.new(trees: @trees, organization: @organization, map_total: @map_total)
      end
    end

    def render_live_feed
      div(class: "p-6 border border-gaia-border bg-gaia-surface-elevated flex flex-col h-full") do
        div(class: "flex justify-between items-center mb-8") do
          h3(class: "text-tiny uppercase tracking-widest text-gaia-text-muted") { t(".feed.title") }
          div(class: "h-1.5 w-1.5 rounded-full bg-emerald-500 animate-ping", aria_hidden: "true")
        end

        div(class: "flex-1 flex flex-col gap-6 overflow-y-auto pr-2 custom-scrollbar") do
          if @events.empty?
            p(class: "text-gaia-text-subtle font-mono text-tiny uppercase tracking-widest text-center py-8") { t(".feed.empty") }
          else
            @events.each { |event| render Dashboard::EventRow.new(event: event) }
          end
        end

        a(
          href: alerts_path,
          class: "mt-8 text-center py-2 border border-gaia-border text-mini uppercase text-gaia-text-muted " \
                 "hover:text-gaia-text hover:border-gaia-border-strong transition-all " \
                 "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary"
        ) { t(".feed.view_all") }
      end
    end
  end
end
