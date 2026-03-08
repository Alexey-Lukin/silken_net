# frozen_string_literal: true

module Api
  module V1
    class TreeFamiliesController < BaseController
      before_action :authorize_admin!
      before_action :set_family, only: [ :show, :edit, :update ]

      # --- РЕЄСТР ГЕНОМІВ ---
      def index
        @pagy, @families = pagy(TreeFamily.alphabetical)

        respond_to do |format|
          format.json do
            render json: {
              data: @families,
              pagy: pagy_metadata(@pagy)
            }
          end
          format.html do
            render_dashboard(
              title: "Biological Constants // The Genomes",
              component: TreeFamilies::Index.new(families: @families, pagy: @pagy)
            )
          end
        end
      end

      # --- ДЕТАЛІ ПОРОДИ ---
      def show
        respond_to do |format|
          format.json { render json: @family }
          format.html do
            render_dashboard(
              title: "Genome Architecture // #{@family.name}",
              component: TreeFamilies::Show.new(family: @family)
            )
          end
        end
      end

      def new
        @family = TreeFamily.new
        render_dashboard(
          title: "Define New Species",
          component: TreeFamilies::Form.new(family: @family)
        )
      end

      def create
        @family = TreeFamily.new(family_params)
        if @family.save
          redirect_to api_v1_tree_families_path, notice: "New species DNA woven into the network."
        else
          render_dashboard(title: "DNA Sequence Error", component: TreeFamilies::Form.new(family: @family))
        end
      end

      def edit
        render_dashboard(
          title: "Refine Genome // #{@family.name}",
          component: TreeFamilies::Form.new(family: @family)
        )
      end

      def update
        if @family.update(family_params)
          redirect_to api_v1_tree_family_path(@family), notice: "Biological constants recalibrated."
        else
          render_dashboard(title: "Recalibration Error", component: TreeFamilies::Form.new(family: @family))
        end
      end

      private

      def set_family
        @family = TreeFamily.find(params[:id])
      end

      def family_params
        params.require(:tree_family).permit(
          :name, :scientific_name, :baseline_impedance, :critical_z_min, :critical_z_max,
          :carbon_sequestration_coefficient,
          :sap_flow_index, :bark_thickness, :foliage_density, :fire_resistance_rating
        )
      end
    end
  end
end
