# frozen_string_literal: true

module Api
  module V1
    class TreesController < BaseController
      # --- ШЕРЕНГА СОЛДАТІВ ---
      # GET /api/v1/clusters/:cluster_id/trees
      def index
        @cluster = Cluster.find(params[:cluster_id])

        # Використовуємо .includes для Zero-Lag продуктивності (захист від N+1)
        @trees = @cluster.trees.active
                               .includes(:wallet, :tree_family)
                               .order(did: :asc)

        render json: @trees.as_json(
          only: [ :id, :did, :status, :latitude, :longitude, :last_seen_at ],
          methods: [ :current_stress, :under_threat? ],
          include: {
            wallet: { only: [ :balance ] },
            tree_family: { only: [ :name ] }
          }
        )
      end

      # --- ПАСПОРТ СОЛДАТА ---
      # GET /api/v1/trees/:id
      def show
        @tree = Tree.find(params[:id])

        # Отримуємо останній лог для виведення сирого імпедансу (Z-value)
        latest_log = @tree.telemetry_logs.recent.first

        render json: {
          tree: @tree.as_json(
            only: [ :id, :did, :status, :last_seen_at ],
            methods: [ :current_stress, :under_threat? ],
            include: {
              wallet: { only: [ :balance ] },
              tree_family: { only: [ :name, :baseline_impedance ] }
            }
          ),
          telemetry: {
            z_value: latest_log&.z_value || 0,
            temperature: latest_log&.temperature_c,
            voltage: latest_log&.voltage_mv,
            last_sync: latest_log&.created_at
          },
          insights: @tree.ai_insights.daily_health_summary.limit(7)
        }
      end
    end
  end
end
