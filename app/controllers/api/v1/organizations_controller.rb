# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Api
  module V1
    class OrganizationsController < BaseController
      # Тільки Адміни Океану (super_admin) мають доступ до глобального реєстру Кланів
      before_action :authorize_super_admin!

      # --- ПЕРЕЛІК КЛАНІВ (The Hierarchy View) ---
      def index
        @pagy, @organizations = pagy(Organization.includes(:clusters, :naas_contracts).all)

        respond_to do |format|
          format.json do
            render json: {
              data: OrganizationBlueprint.render_as_hash(@organizations, view: :index),
              pagy: pagy_metadata(@pagy)
            }
          end
          format.html do
            render_dashboard(
              title: I18n.t("organizations.index_title"),
              component: Organizations::Index.new(organizations: @organizations, pagy: @pagy)
            )
          end
        end
      end

      # --- ПРОФІЛЬ ОРГАНІЗАЦІЇ (Deep Audit) ---
      def show
        @organization = Organization.find(params[:id])
        @clusters = @organization.clusters

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
              title: I18n.t("organizations.show_title", name: @organization.name),
              component: Organizations::Show.new(
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
