# frozen_string_literal: true

module Api
  module V1
    class DashboardController < BaseController
      def index
        org = current_user.organization

        # Агрегація Війська (scoped to organization)
        total_trees = org.trees.count
        active_trees = org.trees.active.count
        health_avg = org.clusters.average(:health_index).to_f.round(2)

        # Агрегація Енергії (Streaming Potential)
        # Середній вольтаж по деревах організації за останню годину
        avg_voltage = TelemetryLog.joins(tree: :cluster)
                                  .where(clusters: { organization_id: org.id })
                                  .where(created_at: 1.hour.ago..Time.current)
                                  .average(:voltage_mv) || 0

        @stats = {
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
        org = current_user.organization

        # Збираємо мікс з останніх алертів, транзакцій та реєстрацій (scoped to organization)
        [
          org.ews_alerts.order(created_at: :desc).limit(3),
          BlockchainTransaction.joins(wallet: { tree: :cluster })
                               .where(clusters: { organization_id: org.id })
                               .order(created_at: :desc).limit(3),
          MaintenanceRecord.joins(:user)
                           .where(users: { organization_id: org.id })
                           .order(created_at: :desc).limit(3)
        ].flatten.sort_by(&:created_at).reverse.first(8)
      end
    end
  end
end
