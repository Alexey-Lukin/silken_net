# frozen_string_literal: true

module Api
  module V1
    class DashboardController < BaseController
      before_action :ensure_organization!, only: :index

      def index
        org = current_user.organization

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
              title: "Citadel Command // Global Overview",
              component: Dashboard::Home.new(stats: @stats, events: @recent_events)
            )
          end
        end
      end

      private

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
        org = current_user.organization

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
