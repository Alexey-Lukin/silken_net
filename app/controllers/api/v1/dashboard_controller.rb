# frozen_string_literal: true

module Api
  module V1
    class DashboardController < BaseController
      def index
        # Агрегація Війська
        total_trees = Tree.count
        active_trees = Tree.active.count
        health_avg = Cluster.all.map(&:health_index).sum / Cluster.count.to_f rescue 0

        # Агрегація Енергії (Streaming Potential)
        # Беремо середній вольтаж по останніх логах усіх активних вузлів
        avg_voltage = TelemetryLog.where(created_at: 1.hour.ago..Time.current).average(:voltage_mv) || 0

        @stats = {
          trees: {
            total: total_trees,
            active: active_trees,
            health_avg: health_avg
          },
          economy: {
            total_scc: Wallet.sum(:scc_balance).to_f.round(4)
          },
          security: {
            active_alerts: EwsAlert.unresolved.count
          },
          energy: {
            avg_voltage: avg_voltage.to_i,
            status: avg_voltage > 3300 ? "STABLE" : "LOW_RESERVE"
          }
        }

        # Останні події для стрічки
        @recent_events = fetch_recent_events

        respond_to do |format|
          format.json { render json: @stats }
          format.html do
            render_dashboard(
              title: "Citadel Command // Global Overview",
              component: Views::Components::Dashboard::Home.new(stats: @stats, events: @recent_events)
            )
          end
        end
      end

      private

      def fetch_recent_events
        # Збираємо мікс з останніх алертів, транзакцій та реєстрацій
        [
          EwsAlert.order(created_at: :desc).limit(3),
          BlockchainTransaction.order(created_at: :desc).limit(3),
          MaintenanceRecord.order(created_at: :desc).limit(3)
        ].flatten.sort_by(&:created_at).reverse.first(8)
      end
    end
  end
end
