# frozen_string_literal: true

module Api
  module V1
    class TreesController < BaseController
      # --- ШЕРЕНГА СОЛДАТІВ (Sector Grid) ---
      # GET /api/v1/clusters/:cluster_id/trees
      def index
        @cluster = Cluster.find(params[:cluster_id])
        @trees = @cluster.trees
                         .includes(:wallet, :tree_family, :hardware_key)
                         .order(did: :asc)

        respond_to do |format|
          format.json do
            render json: @trees.as_json(
              only: [ :id, :did, :status, :latitude, :longitude, :last_seen_at ],
              methods: [ :current_stress, :under_threat? ],
              include: {
                wallet: { only: [ :balance ] },
                tree_family: { only: [ :name ] }
              }
            )
          end
          format.html do
            render_dashboard(
              title: "Sector Matrix // #{@cluster.name}",
              component: Views::Components::Trees::Index.new(cluster: @cluster, trees: @trees)
            )
          end
        end
      end

      # --- ПАСПОРТ СОЛДАТА (Deep Audit) ---
      # GET /api/v1/trees/:id
      def show
        @tree = Tree.find(params[:id])
        @latest_log = @tree.telemetry_logs.order(created_at: :desc).first
        @insights = @tree.ai_insights.daily_health_summary.limit(7)

        respond_to do |format|
          format.json do
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
                z_value: @latest_log&.z_value || 0,
                temperature: @latest_log&.temperature_c,
                voltage: @latest_log&.voltage_mv,
                last_sync: @latest_log&.created_at
              },
              insights: @insights
            }
          end
          format.html do
            render_dashboard(
              title: "Soldier Identity // #{@tree.did}",
              component: Views::Components::Trees::Show.new(tree: @tree)
            )
          end
        end
      end
    end
  end
end
