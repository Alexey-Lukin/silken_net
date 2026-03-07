# frozen_string_literal: true

module Api
  module V1
    class TreesController < BaseController
      # --- ШЕРЕНГА СОЛДАТІВ (Sector Grid) ---
      # GET /api/v1/clusters/:cluster_id/trees
      def index
        @cluster = current_user.organization.clusters.find(params[:cluster_id])
        @pagy, @trees = pagy(
          @cluster.trees
                  .includes(:wallet, :tree_family, :hardware_key)
                  .order(did: :asc)
        )

        respond_to do |format|
          format.json do
            render json: {
              trees: TreeBlueprint.render_as_hash(@trees, view: :index),
              pagy: { page: @pagy.page, limit: @pagy.limit, count: @pagy.count, pages: @pagy.last }
            }
          end
          format.html do
            render_dashboard(
              title: "Sector Matrix // #{@cluster.name}",
              component: Trees::Index.new(cluster: @cluster, trees: @trees)
            )
          end
        end
      end

      # --- ПАСПОРТ СОЛДАТА (Deep Audit) ---
      # GET /api/v1/trees/:id
      def show
        @tree = current_user.organization.trees.find(params[:id])
        @latest_log = @tree.telemetry_logs.order(created_at: :desc).first
        @insights = @tree.ai_insights.daily_health_summary.limit(7)

        respond_to do |format|
          format.json do
            render json: {
              tree: TreeBlueprint.render_as_hash(@tree, view: :show),
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
              component: Trees::Show.new(tree: @tree)
            )
          end
        end
      end
    end
  end
end
