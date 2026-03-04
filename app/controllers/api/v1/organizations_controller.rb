# frozen_string_literal: true

module Api
  module V1
    class OrganizationsController < BaseController
      # Тільки Адміни Океану (super_admin) мають доступ до глобального реєстру Кланів
      before_action :authorize_super_admin!

      # --- ПЕРЕЛІК КЛАНІВ (The Hierarchy View) ---
      def index
        @organizations = Organization.includes(:clusters, :naas_contracts).all

        respond_to do |format|
          format.json do
            render json: OrganizationBlueprint.render(@organizations, view: :index)
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
          total_trees: @organization.cached_trees_count,
          carbon_minted: @organization.naas_contracts.sum(:emitted_tokens).to_f.round(2)
        }

        respond_to do |format|
          format.json do
            render json: {
              organization: OrganizationBlueprint.render_as_hash(@organization, view: :show),
              clusters: ClusterBlueprint.render_as_hash(@clusters),
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
