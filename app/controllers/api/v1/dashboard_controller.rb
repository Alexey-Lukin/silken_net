# frozen_string_literal: true

module Api
  module V1
    class DashboardController < BaseController
      # GET /api/v1/dashboard
      def index
        # Агрегація істини для головного екрана
        @stats = {
          trees: {
            total: Tree.count,
            active: Tree.where(status: :active).count,
            health_avg: Cluster.average(:health_score) || 100
          },
          economy: {
            total_scc: Wallet.sum(:scc_balance).to_f.round(4),
            active_contracts: NaasContract.where(status: :active).count
          },
          security: {
            active_alerts: EwsAlert.where(resolved_at: nil).count,
            gateways_online: Gateway.where("last_seen_at > ?", 10.minutes.ago).count
          },
          clusters: Cluster.all.includes(:organization)
        }

        respond_to do |format|
          format.json { render json: @stats }
          format.html do
            render_dashboard(
              title: "Global Command Center",
              component: Views::Components::Dashboard::Home.new(stats: @stats)
            )
          end
        end
      end
    end
  end
end
