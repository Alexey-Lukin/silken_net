# frozen_string_literal: true

module Api
  module V1
    # Видалення окремого фото з MaintenanceRecord.
    # DELETE /api/v1/maintenance_records/:maintenance_record_id/photos/:id
    class MaintenanceRecordPhotosController < BaseController
      before_action :authorize_forester!
      before_action :set_record
      before_action :set_photo

      def destroy
        @photo.purge_later # async — не блокуємо запит, S3 deletion в Sidekiq
        respond_to do |format|
          format.json { render json: { message: "Фото видалено з Evidence Matrix." }, status: :ok }
          format.html { redirect_to api_v1_maintenance_record_path(@record), notice: "Photo removed." }
        end
      end

      private

      def set_record
        org_cluster_ids = current_user.organization.clusters.select(:id)

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
        render json: { error: "Фото не знайдено." }, status: :not_found
      end
    end
  end
end
