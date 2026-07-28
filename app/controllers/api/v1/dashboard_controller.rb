# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Api
  module V1
    class DashboardController < BaseController
      def index
        org = acting_organization!

        @stats = Rails.cache.fetch("dashboard_stats_org_#{org.id}", expires_in: 2.minutes) do
          # Агрегація Війська (scoped to organization)
          total_trees = org.trees.count
          active_trees = org.trees.active.count
          health_avg = org.clusters.average(:health_index).to_f.round(2)

          # Агрегація Енергії (Streaming Potential)
          # [ВИПРАВЛЕНО: Dashboard avg_voltage JOIN]:
          # Замість важкого JOIN на telemetry_logs (мільйони рядків за годину)
          # використовуємо вже денормалізовану колонку latest_voltage_mv із таблиці trees.
          # mark_seen! оновлює latest_voltage_mv при кожному пакеті телеметрії,
          # тому середнє по активних деревах відображає поточний стан флоту точніше.
          avg_voltage = org.trees.active.average(:latest_voltage_mv) || 0

          {
            trees: {
              total: total_trees,
              active: active_trees,
              health_avg: health_avg
            },
            economy: {
              total_scc: org.wallets.sum(:balance).to_f.round(4)
            },
            security: {
              active_alerts: org.ews_alerts.unresolved.count
            },
            energy: {
              avg_voltage: avg_voltage.to_i,
              status: avg_voltage > 3300 ? "STABLE" : "LOW_RESERVE"
            },
            global_onchain_carbon: fetch_global_onchain_carbon
          }
        end

        # Останні події для стрічки
        @recent_events = fetch_recent_events

        respond_to do |format|
          format.json { render json: @stats }
          format.html do
            render_dashboard(
              title: I18n.t("dashboard.index_title"),
              component: Dashboard::Home.new(
                stats: @stats,
                events: @recent_events,
                trees: map_trees(org),
                organization: org
              )
            )
          end
        end
      end

      private

      # Стеля першого рендеру геопросторової матриці. Leaflet тримає таку кількість
      # маркерів без кластеризації; понад неї сторінка показує ПІДМНОЖИНУ флоту —
      # свідомий борг, бо кластеризація маркерів = нова JS-залежність (→ 00_07 UI.4).
      # Живі оновлення ліміту не знають: broadcast_replace у ціль, якої нема в DOM,
      # Turbo тихо ігнорує.
      MAP_NODE_LIMIT = 500

      # Лише геолоковані дерева організації — і лише для html-гілки: JSON-споживач
      # мапи не рендерить, тож не платить за цей SELECT. N+1 тут немає за
      # побудовою: `Dashboard::MapNode` читає виключно колонки `trees`
      # (latitude/longitude/status + денормалізовані latest_stress_index,
      # latest_voltage_mv), жодної асоціації.
      # `order(:id)` не косметика: без нього `limit` віддає НЕДЕТЕРМІНОВАНУ
      # підмножину — понад стелею глядач бачив би різні дерева між
      # перезавантаженнями, а це виглядає як зникання вузлів, не як ліміт.
      def map_trees(org)
        org.trees.geolocated.order(:id).limit(MAP_NODE_LIMIT)
      end

      # [ВИПРАВЛЕНО: Sync RPC Trap]: Кешуємо GraphQL результат з TheGraph на 5 хвилин,
      # щоб не блокувати кожен запит дашборду на 2-10 секунд.
      def fetch_global_onchain_carbon
        Rails.cache.fetch("global_onchain_carbon", expires_in: 5.minutes) do
          Timeout.timeout(10) do
            TheGraph::QueryService.new.fetch_total_carbon_minted
          end
        end
      rescue StandardError
        0
      end

      def fetch_recent_events
        org = acting_organization!

        # Збираємо мікс з останніх алертів, транзакцій та реєстрацій (scoped to organization)
        [
          org.ews_alerts.includes(:cluster).order(created_at: :desc).limit(3),
          BlockchainTransaction.joins(wallet: { tree: :cluster })
                               .includes(wallet: { tree: :cluster })
                               .where(clusters: { organization_id: org.id })
                               .order(created_at: :desc).limit(3),
          MaintenanceRecord.joins(:user)
                           .includes(:user)
                           .where(users: { organization_id: org.id })
                           .order(created_at: :desc).limit(3)
        ].flatten.sort_by(&:created_at).reverse.first(8)
      end
    end
  end
end
