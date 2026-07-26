# SPDX-License-Identifier: AGPL-3.0-or-later
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
              data: TreeBlueprint.render_as_hash(@trees, view: :index),
              pagy: { page: @pagy.page, limit: @pagy.limit, count: @pagy.count, pages: @pagy.last }
            }
          end
          format.html do
            render_dashboard(
              title: "Sector Matrix // #{@cluster.name}",
              component: Trees::Index.new(cluster: @cluster, trees: @trees, pagy: @pagy)
            )
          end
        end
      end

      # --- ПАСПОРТ СОЛДАТА (Deep Audit) ---
      # GET /api/v1/trees/:id
      def show
        @tree = current_user.organization.trees
                  .includes(:tree_family, :hardware_key, :wallet, :cluster)
                  .find(params[:id])
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
            @recent_logs = @tree.telemetry_logs.order(created_at: :desc).limit(10)
            @maintenance_records = @tree.maintenance_records.includes(:user).order(performed_at: :desc).limit(20)
            render_dashboard(
              title: "Soldier Identity // #{@tree.did}",
              component: Trees::Show.new(
                tree: @tree,
                latest_log: @latest_log,
                recent_logs: @recent_logs,
                maintenance_history: @maintenance_records
              )
            )
          end
        end
      end
      # --- ЦИФРОВИЙ ЖИТТЄПИС (Tree Chronicle) ---
      # GET /api/v1/trees/:id/chronicle
      # HTML: Turbo Frame для lazy-loading у Trees::Show
      # JSON: Масив хронологічних подій
      def chronicle
        @tree = current_user.organization.trees.find(params[:id])
        result = TreeChronicleService.call(tree: @tree, page: params[:page], per_page: 20)

        respond_to do |format|
          format.json do
            render json: {
              data: result[:entries].map { |e| chronicle_entry_hash(e) },
              pagy: { page: result[:pagy].page, limit: result[:pagy].limit,
                      count: result[:pagy].count, pages: result[:pagy].last }
            }
          end
          format.html do
            render Trees::Chronicle.new(
              tree: @tree,
              entries: result[:entries],
              pagy: result[:pagy]
            ), layout: false
          end
        end
      end

      private

      def chronicle_entry_hash(entry)
        {
          date: entry.date&.iso8601,
          event_type: entry.event_type,
          icon: entry.icon,
          title: entry.title,
          description: entry.description,
          severity: entry.severity,
          source_type: entry.source_type,
          source_id: entry.source_id
        }
      end
    end
  end
end
