# frozen_string_literal: true

module Api
  module V1
    class OrganizationsController < BaseController
      # Тільки Адміни Океану можуть бачити всі організації
      before_action :authorize_admin!

      # --- ПЕРЕЛІК КЛАНІВ ---
      # GET /api/v1/organizations
      def index
        @organizations = Organization.includes(:clusters, :naas_contracts)

        render json: @organizations.as_json(
          only: [ :id, :name, :crypto_public_address, :created_at ],
          methods: [ :total_clusters, :total_invested ]
        )
      end

      # --- ПРОФІЛЬ ОРГАНІЗАЦІЇ ---
      # GET /api/v1/organizations/:id
      def show
        @organization = Organization.find(params[:id])

        render json: {
          organization: @organization,
          clusters: @organization.clusters.as_json(methods: [ :health_index ]),
          performance: {
            total_trees: @organization.trees.count,
            carbon_minted: @organization.naas_contracts.sum(:emitted_tokens)
          }
        }
      end
    end
  end
end
