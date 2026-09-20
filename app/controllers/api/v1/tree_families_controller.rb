# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Api
  module V1
    class TreeFamiliesController < BaseController
      before_action :authorize_admin!
      # [SEC]: TreeFamily = ГЛОБАЛЬНА довідкова таблиця (не org-scoped), і її
      # поля мутує super_admin, бо радіус вибуху глобальний. ДВА поля, ДВА
      # різні радіуси — не злипати:
      #   • `carbon_sequestration_coefficient` → `Wallet#credit!` → mint. Гроші,
      #     живі сьогодні, для ВСІХ org.
      #   • `critical_z_min/max` → ⛔ [E.64 ⚖️ 2026-09-05] НЕ називати це
      #     anti-fraud смугою. Anti-fraud = DCI, а той судить за
      #     `Tree#device_lorenz_thresholds` (зашиті глобальні
      #     2.0/45.0 — прошивку per-species значеннями не провіжинять, FW.8);
      #     СЕРВЕРНУ Z-гілку вердикту знято (Z є DCI-only, `05_05 §8.1`).
      #     ⚠️ «Знято» має точний периметр: пристрійна гілка
      #     `bio_status_stress?` → `severe_drought` СТОЇТЬ у коді
      #     (`AlertDispatchService`) і мовчить не тому, що її прибрали, а тому
      #     що недосяжна ЗА КОНСТРУКЦІЄЮ (ρ-clamp тримає `z_eq ≥ 9`; нуль
      #     випадків на 5 000 прогонів). ⛔ Не знімати її «як мертву».
      #     ⚠️ І читачів у пари БАГАТО — валідації `TreeFamily` (`comparison`
      #     та межі `optimal_z_target`, живі саме в цьому запиті), форма й
      #     таблиця адмінки, спекове дзеркало `Attractor.homeostatic?`. Точне
      #     твердження не «споживач один», а **пара не виносить ЖОДНОГО
      #     вердикту — ні алерту, ні DCI, ні мінту** (те саме формулювання, що
      #     в сиблінгу `TreeFamilies::Index`); єдиний ВЕРДИКТНИЙ споживач
      #     сплячий — `Tree#effective_lorenz_thresholds` → `OtaPackagerService`
      #     (`CMD_SET_THRESHOLDS 0x9A`), тобто «що слати вузлові». Захист
      #     лишається, бо ПІСЛЯ FW.8 ця пара стане смугою, за якою судить сам
      #     пристрій; підстава — майбутній радіус, не сьогоднішній детект.
      # (on-chain параметри вже Timelock-governed, off-chain константи
      # заслуговують на еквівалентний захист.)
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
              component: TreeFamilies::Index.new(families: @families, pagy: @pagy, current_user: current_user)
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
            format.html { redirect_to tree_families_path, success: I18n.t("flash.tree_families.created") }
          end
        else
          respond_to do |format|
            format.json { render_validation_error(@family) }
            # [SEC.25] `status:` тут несучий, а не косметика: Turbo Drive вимагає, щоб
            # відповідь на сабміт була або редиректом, або 4xx/5xx — на `200` без
            # редиректу воно кидає «Form responses must redirect to another location»
            # у консоль і НЕ оновлює сторінку взагалі. Тобто без цього рядка форма з
            # помилкою виглядає для оператора як мертва кнопка. Дзеркалить JSON-гілку
            # рядком вище, яка 422 віддавала завжди.
            format.html do
              render_dashboard(title: I18n.t("tree_families.create_error_title"),
                               component: TreeFamilies::Form.new(family: @family),
                               status: :unprocessable_content)
            end
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
            format.html { redirect_to tree_family_path(@family), success: I18n.t("flash.tree_families.updated") }
          end
        else
          respond_to do |format|
            format.json { render_validation_error(@family) }
            format.html do
              render_dashboard(title: I18n.t("tree_families.update_error_title"),
                               component: TreeFamilies::Form.new(family: @family),
                               status: :unprocessable_content)
            end
          end
        end
      end

      private

      def set_family
        @family = TreeFamily.find(params[:id])
      end

      def family_params
        params.require(:tree_family).permit(
          :name, :scientific_name, :critical_z_min, :critical_z_max,
          :carbon_sequestration_coefficient,
          :bark_thickness, :foliage_density, :fire_resistance_rating
        )
      end
    end
  end
end
