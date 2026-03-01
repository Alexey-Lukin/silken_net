# frozen_string_literal: true

module Api
  module V1
    class OrganizationsController < BaseController
      # Тільки Адміни Океану мають доступ до глобального реєстру Кланів
      before_action :authorize_admin!

      # --- ПЕРЕЛІК КЛАНІВ (The Hierarchy View) ---
      def index
        @organizations = Organization.includes(:clusters, :naas_contracts).all

        respond_to do |format|
          format.json do
            render json: @organizations.as_json(
              only: [ :id, :name, :crypto_public_address, :created_at ],
              methods: [ :total_clusters, :total_invested ]
            )
          end
          format.html do
            render_dashboard(
              title: "Organization Registry // The Clans",
              component: Views::Components::Organizations::Index.new(organizations: @organizations)
            )
          end
        end
      end

      # --- ПРОФІЛЬ ОРГАНІЗАЦІЇ (Deep Audit) ---
      def show
        @organization = Organization.find(params[:id])
        @clusters = @organization.clusters.includes(:trees)
        
        @performance = {
          total_trees: @organization.trees.count,
          carbon_minted: @organization.naas_contracts.sum(:emitted_tokens).to_f.round(2)
        }

        respond_to do |format|
          format.json do
            render json: {
              organization: @organization,
              clusters: @clusters.as_json(methods: [ :health_index ]),
              performance: @performance
            }
          end
          format.html do
            render_dashboard(
              title: "Clan Profile // #{@organization.name}",
              component: Views::Components::Organizations::Show.new(
                organization: @organization, 
                clusters: @clusters,
                performance: @performance
              )
            )
          end
        end
      end
    end
  end
end
