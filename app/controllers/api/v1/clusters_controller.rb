# frozen_string_literal: true

module Api
  module V1
    class ClustersController < BaseController
      # Дозволяємо перегляд усім автентифікованим користувачам
      # (Інвестори бачать фінанси, Патрульні — загрози)

      # --- СПИСОК СЕКТОРІВ (The Map View) ---
      # GET /api/v1/clusters
      def index
        @clusters = Cluster.all.includes(:organization)

        # Передаємо дані, оптимізовані для рендерингу мапи (Leaflet/MapLibre)
        render json: @clusters.as_json(
          only: [ :id, :name, :region, :geojson_polygon ],
          methods: [ :health_index, :total_active_trees, :geo_center, :active_threats? ]
        )
      end

      # --- ДЕТАЛІ СЕКТОРА (The Deep Dive) ---
      # GET /api/v1/clusters/:id
      def show
        @cluster = Cluster.find(params[:id])

        render json: @cluster.as_json(
          include: {
            gateways: {
              only: [ :uid, :state, :last_seen_at, :latitude, :longitude ]
            },
            naas_contracts: {
              only: [ :id, :status, :total_value, :emitted_tokens ]
            }
          },
          methods: [ :health_index, :total_active_trees, :geo_center ]
        )
      end
    end
  end
end
