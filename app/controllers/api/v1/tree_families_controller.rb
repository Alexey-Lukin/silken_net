# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Api
  module V1
    class TreeFamiliesController < BaseController
      before_action :authorize_admin!
      # [SEC]: TreeFamily = ГЛОБАЛЬНА довідкова таблиця (не org-scoped), її поля
      # живлять money+fraud-математику (carbon_sequestration_coefficient → mint;
      # critical_z_min/max → anti-fraud смуга). Мутація будь-яким org-admin
      # інфлейтила б мінтинг / послаблювала fraud-детект для ВСІХ org → мутації
      # лише super_admin (on-chain параметри вже Timelock-governed, off-chain
      # константи заслуговують на еквівалентний захист).
      before_action :authorize_super_admin!, only: [ :new, :create, :edit, :update ]
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
              title: I18n.t("tree_families.index_title"),
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
              title: I18n.t("tree_families.show_title", name: @family.name),
              component: TreeFamilies::Show.new(family: @family)
            )
          end
        end
      end

      def new
        @family = TreeFamily.new
        render_dashboard(
          title: I18n.t("tree_families.new_title"),
          component: TreeFamilies::Form.new(family: @family)
        )
      end

      def create
        @family = TreeFamily.new(family_params)
        if @family.save
          respond_to do |format|
            format.json { render json: { data: @family }, status: :created }
            format.html { redirect_to api_v1_tree_families_path, notice: "New species DNA woven into the network." }
          end
        else
          respond_to do |format|
            format.json { render_validation_error(@family) }
            format.html { render_dashboard(title: I18n.t("tree_families.create_error_title"), component: TreeFamilies::Form.new(family: @family)) }
          end
        end
      end

      def edit
        render_dashboard(
          title: I18n.t("tree_families.edit_title", name: @family.name),
          component: TreeFamilies::Form.new(family: @family)
        )
      end

      def update
        if @family.update(family_params)
          respond_to do |format|
            format.json { render json: { data: @family } }
            format.html { redirect_to api_v1_tree_family_path(@family), notice: "Biological constants recalibrated." }
          end
        else
          respond_to do |format|
            format.json { render_validation_error(@family) }
            format.html { render_dashboard(title: I18n.t("tree_families.update_error_title"), component: TreeFamilies::Form.new(family: @family)) }
          end
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
