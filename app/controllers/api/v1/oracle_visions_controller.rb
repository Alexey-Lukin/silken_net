# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Api
  module V1
    class OracleVisionsController < BaseController
      before_action :authorize_forester!

      # GET /oracle_visions
      def index
        org = acting_organization!

        # Використовуємо upcoming для прогнозів, оскільки strategic_forecasts може бути відсутнім.
        # [SCOPE FIX]: Раніше повертали глобальні AiInsight — інвестор з org A бачив
        # прогнози для org B. Саме правило належності живе на моделі
        # (`AiInsight.for_organization` — три гілки поліморфного `analyzable`), бо
        # [SEC.26] дало йому другого споживача поза цим контролером.
        @visions = AiInsight.for_organization(org).upcoming.order(target_date: :asc).limit(10)

        # [FINANCIAL ENGINE]: Розрахунок "Очікуваного врожаю" (SCC Yield)
        # Оракул обчислює потенційну емісію на наступні 24 години на основі живого пульсу лісу.
        @scc_yield = calculate_expected_yield(org)

        respond_to do |format|
          # [ARCH.84] `emission_forecast` лишається ЧИСЛОМ (додатковий ключ, не зміна
          # форми), а покриття їде поруч: скільки дерев із скількох стоїть за цим
          # прогнозом. Число без покриття є твердженням про весь ліс.
          format.json do
            render json: {
              visions: @visions,
              emission_forecast: @scc_yield[:value],
              emission_forecast_coverage: {
                measured: @scc_yield[:measured],
                total: @scc_yield[:total]
              }
            }
          end
          format.html do
            render_dashboard(
              title: I18n.t("oracle_visions.index_title"),
              component: OracleVisions::Index.new(
                visions: @visions,
                emission_forecast: @scc_yield[:value],
                forecast_measured: @scc_yield[:measured],
                forecast_total: @scc_yield[:total]
              )
            )
          end
        end
      end

      private

      # 🧬 Алгоритм Кенозису для фінансового прогнозування
      # [TENANT-ISOLATION FIX]: Cache key per-org. Previously a single global
      # key (`oracle_expected_yield_24h`) leaked the protocol-wide total across
      # tenants — an investor at org A would see org B's yield. Cache is now
      # keyed by org id; the inner Tree scope is also restricted to the org.
      def calculate_expected_yield(org)
        Rails.cache.fetch(Organization.expected_yield_cache_key(org.id), expires_in: 1.hour) do
          threshold = TokenomicsEvaluatorWorker.emission_threshold
          total_potential = 0.0
          measured = 0
          total = 0

          # 🔴 [ARCH.84] Невиміряне дерево ПРОПУСКАЄМО — але разом із покриттям, і
          # саме це робить пропуск законним. Доти `current_stress` віддавав `0.0`,
          # тобто множник `(1.0 − 0)` = **повна вага здоровʼя**: щойно розгорнутий
          # вузол, який ще не бачив нічного проходу, віддавав у прогноз увесь свій
          # sap як ідеально здоровий. Після зняття підстановки `1.0 - nil` — це
          # `TypeError`, тобто 500 на всьому ендпоінті, а не зіпсована комірка.
          # ⛔ Мовчазний скіп сюди не годиться: число, що тихо викидає частину
          # знаменника, не відповідає на «а звідки ти це знаєш» — це нога місії
          # **«правдиво»** та її зворотний тест (`00_01 §1.1`, дзеркало — `04_01 §3`).
          # ⚠️ Тут доти стояло «проти ноги «невідбирано»» — хибна адреса: канон
          # операціоналізує те слово як НЕПРИВЛАСНЕННЯ (defensive publication,
          # копілефт, non-assertion pledge), а не як «без відбору». Виправлено
          # 2026-08-15; аргумент лишився той самий, змінилась лише нога.
          # Тому число їде з `measured`/`total`, як `Cluster.health_coverage`.
          # ⊕ `.includes(:ai_insights)` знято: `current_stress` читає денормалізовану
          # колонку, тож eager-load був мертвий.
          # ✅ [PERF.1] N+1 на `latest_telemetry_log` знято: `find_in_batches` + ОДИН
          # `DISTINCT ON` на батч (`TelemetryLog.latest_per_tree` — дім там, бо питання
          # «останній рядок на дерево» належить логу, не контролеру). Відповідь та сама
          # ДОСЛІВНО: часової межі не додано, бо вона змінила б семантику — дерево,
          # що мовчить довше вікна, віддало б порожньо замість останнього відомого
          # sap. ⚠️ Тому виграш тут у КІЛЬКОСТІ запитів (N → 1 на батч), а не в обсязі
          # скану: партиції проходяться всі, і стеля названа в самому скоупі.
          org.trees.active.find_in_batches(batch_size: 1000) do |batch|
            sap_by_tree = TelemetryLog.latest_per_tree(batch.map(&:id))
                                      .to_h { |log| [ log.tree_id, log.sap_flow ] }

            batch.each do |tree|
              total += 1
              stress = tree.current_stress
              # 🔴 [ARCH.84] `measured` доти рахував ОДИН вимір, а число залежало
              # від ДВОХ: стрес відсіювався чесно, а `sap_flow` підставлявся
              # (`|| 0.0`) вже ПІСЛЯ інкремента — тобто дерево без телеметрії
              # входило в покриття як виміряне й додавало в чисельник нуль.
              # Покриття, заведене саме щоб зробити прогноз чесним, засвідчувало
              # само себе. `sap_flow` nullable, і нуль на ньому ДОСЯЖНИЙ (спляче
              # дерево), тож два стани були одним числом.
              sap_index = sap_by_tree[tree.id]
              next if stress.nil? || sap_index.nil?

              measured += 1
              total_potential += sap_index * (1.0 - stress)
            end
          end

          # `.to_f` НЕСУЧИЙ, не косметика: `sap_flow` — `decimal`, тож після першого ж
          # дерева `total_potential` стає BigDecimal (зараження йде в один бік), а
          # `.round(4)` на ньому повертає BigDecimal — тобто прогноз їхав би на екран
          # із сирою точністю схеми замість чотирьох знаків. Доти він там ще й ЗНИКАВ,
          # поки Phlex не вмів друкувати цей тип узагалі (`04_04 §2`).
          # У кеш кладемо СКАЛЯРИ, не Struct — та сама дисципліна, що в
          # `dashboard_controller` після [ARCH.84].
          {
            value: ((total_potential * 24) / threshold).to_f.round(4),
            measured: measured,
            total: total
          }
        end
      end
    end
  end
end
