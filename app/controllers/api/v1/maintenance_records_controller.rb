# frozen_string_literal: true

module Api
  module V1
    class MaintenanceRecordsController < BaseController
      # Тільки Патрульні та Адміни можуть фіксувати втручання
      before_action :authorize_forester!

      # --- ЖУРНАЛ ВТРУЧАНЬ ---
      # GET /api/v1/maintenance_records
      # Параметри: ?maintainable_type=Tree&maintainable_id=42
      def index
        @records = MaintenanceRecord.includes(:user, :maintainable)
                                    .order(performed_at: :desc)

        if params[:maintainable_type].present? && params[:maintainable_id].present?
          @records = @records.where(
            maintainable_type: params[:maintainable_type],
            maintainable_id: params[:maintainable_id]
          )
        end

        render json: @records.as_json(
          include: {
            user: { only: [:id, :first_name, :last_name] },
            maintainable: { only: [:id, :did, :uid] }
          }
        )
      end

      # --- ФІКСАЦІЯ ЗЦІЛЕННЯ ---
      # POST /api/v1/maintenance_records
      def create
        # Створюємо запис, прив'язаний до поточного Патрульного
        @record = current_user.maintenance_records.build(maintenance_params)

        if @record.save
          # [СИНХРОНІЗАЦІЯ]: Колбек heal_ecosystem! у моделі вже запустив:
          # 1. Оновлення статусу пристрою.
          # 2. Закриття EwsAlert (якщо ews_alert_id передано).
          
          render json: {
            message: "Запис про зцілення зафіксовано. Екосистема оновлена.",
            record: @record
          }, status: :created
        else
          render_validation_error(@record)
        end
      end

      # --- ДЕТАЛІ ОГЛЯДУ ---
      # GET /api/v1/maintenance_records/:id
      def show
        @record = MaintenanceRecord.find(params[:id])
        render json: @record
      end

      private

      def maintenance_params
        params.require(:maintenance_record).permit(
          :maintainable_id, 
          :maintainable_type, 
          :ews_alert_id,
          :action_type, 
          :notes, 
          :performed_at
        )
      end
    end
  end
end
