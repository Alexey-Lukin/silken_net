# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Api
  module V1
    class ClustersController < BaseController
      # Дозволяємо перегляд усім автентифікованим користувачам
      # (Інвестори бачать фінанси, Патрульні — загрози)

      # --- СПИСОК СЕКТОРІВ (The Map View / Dashboard Grid) ---
      # GET /api/v1/clusters
      def index
        # Скоупимо до організації поточного користувача (Security Scope)
        # active_threats? використовує EXISTS з composite index — includes не потрібен.
        # health_index та active_trees_count — денормалізовані колонки на clusters.
        @pagy, @clusters = pagy(current_user.organization.clusters)

        respond_to do |format|
          # 1. API Response (Mobile / Externals)
          format.json do
            render json: {
              data: ClusterBlueprint.render_as_hash(@clusters),
              pagy: pagy_metadata(@pagy)
            }
          end

          # 2. Dashboard Response (Phlex + Hotwire)
          format.html do
            render_dashboard(
              title: "Cluster Atlas",
              component: Clusters::Grid.new(clusters: @clusters, pagy: @pagy)
            )
          end
        end
      end

      # --- ДЕТАЛІ СЕКТОРА (The Deep Dive / Sector Matrix) ---
      # GET /api/v1/clusters/:id
      def show
        @cluster = current_user.organization.clusters.find(params[:id])

        respond_to do |format|
          # 1. API Response
          format.json do
            render json: ClusterBlueprint.render_as_hash(@cluster, view: :show)
          end

          # 2. Dashboard Response
          format.html do
            @gateways = @cluster.gateways.order(:uid).limit(50)
            @recent_alerts = @cluster.ews_alerts.unresolved.order(created_at: :desc).limit(5)
            render_dashboard(
              title: "Sector: #{@cluster.name}",
              component: Clusters::Show.new(
                cluster: @cluster,
                gateways: @gateways,
                recent_alerts: @recent_alerts
              )
            )
          end
        end
      end
    end
  end
end
