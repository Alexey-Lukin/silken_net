# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Api
  module V1
    # Видалення окремого фото з MaintenanceRecord.
    # DELETE /api/v1/maintenance_records/:maintenance_record_id/photos/:id
    class MaintenanceRecordPhotosController < BaseController
      before_action :authorize_forester!
      before_action :set_record
      # [UI.6] Дзеркало гарда батьківського контролера, якого тут бракувало. Коміт, що
      # закрив «Forester #2 within the same org» на `edit`/`update`/`verify`, цього шляху
      # не торкнувся — а він мутує ТОЙ САМИЙ запис, тож будь-який форестер організації
      # видаляв фотодокази з чужого. Наслідок важчий за батьківський: там посадка мʼяка
      # (403), тут дія ПРОХОДИЛА — незворотно (`purge_later` → S3) і безслідно
      # (`MaintenanceRecord` поза `Auditable`-периметром, [SEC.28]).
      # Стоїть ПІСЛЯ `set_record`, бо читає `@record`; без `only:` — екшен тут один.
      before_action :authorize_record_mutation!
      before_action :set_photo

      def destroy
        @photo.purge_later # async — не блокуємо запит, S3 deletion в Sidekiq
        respond_to do |format|
          format.json { render json: { message: I18n.t("flash.maintenance.photo_deleted") }, status: :ok }
          format.html { redirect_to api_v1_maintenance_record_path(@record), notice: I18n.t("flash.maintenance.photo_deleted") }
        end
      end

      private

      # Формула — не тут: дім = `MaintenanceRecord#mutable_by?`, той самий предикат, що
      # читає батьківський гард і що фільтрує кнопку в `PhotoCard`.
      #
      # ⚠️ Посадка ведеться на сторінку ЗАПИСУ, а не на index (як у батька): кнопка «×»
      # живе саме на `show`, тож викидати з неї глядача — регрес там, де відмова мала б
      # лише пояснити. HTML-гілка обовʼязкова, бо «×» — це `button_to` з браузера:
      # голий `render_forbidden` віддав би форестеру JSON-блоб ([SEC.25]).
      def authorize_record_mutation!
        return if @record.mutable_by?(current_user)

        respond_to do |format|
          format.json { render_forbidden }
          format.html do
            redirect_to api_v1_maintenance_record_path(@record), alert: I18n.t("errors.api.forbidden")
          end
        end
      end

      def set_record
        org_cluster_ids = acting_organization!.clusters.select(:id)

        @record = MaintenanceRecord.where(
          "(maintainable_type = 'Tree' AND maintainable_id IN (?)) OR " \
          "(maintainable_type = 'Gateway' AND maintainable_id IN (?))",
          Tree.where(cluster_id: org_cluster_ids).select(:id),
          Gateway.where(cluster_id: org_cluster_ids).select(:id)
        ).find(params[:maintenance_record_id])
      end

      def set_photo
        @photo = @record.photos.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: I18n.t("flash.maintenance.photo_not_found") }, status: :not_found
      end
    end
  end
end
