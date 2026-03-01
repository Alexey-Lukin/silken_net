# frozen_string_literal: true

module Api
  module V1
    class MaintenanceRecordsController < BaseController
      before_action :authorize_forester!

      # --- ЖУРНАЛ ВТРУЧАНЬ ---
      def index
        @records = MaintenanceRecord.includes(:user, :maintainable)
                                    .order(performed_at: :desc)

        if params[:maintainable_type].present? && params[:maintainable_id].present?
          @records = @records.where(
            maintainable_type: params[:maintainable_type],
            maintainable_id: params[:maintainable_id]
          )
        end

        respond_to do |format|
          format.json do
            render json: @records.as_json(
              include: {
                user: { only: [ :id, :first_name, :last_name ] },
                maintainable: { only: [ :id, :did, :uid ] }
              }
            )
          end
          format.html do
            render_dashboard(
              title: "Maintenance Log // Records of Healing",
              component: Views::Components::Maintenance::Index.new(records: @records)
            )
          end
        end
      end

      # --- НОВИЙ ЗАПИС (Форма) ---
      def new
        @record = current_user.maintenance_records.build(
          maintainable_type: params[:maintainable_type] || "Tree",
          maintainable_id: params[:maintainable_id],
          ews_alert_id: params[:ews_alert_id]
        )

        render_dashboard(
          title: "New Maintenance Ritual",
          component: Views::Components::Maintenance::Form.new(record: @record)
        )
      end

      # --- ФІКСАЦІЯ ЗЦІЛЕННЯ ---
      def create
        @record = current_user.maintenance_records.build(maintenance_params)

        if @record.save
          respond_to do |format|
            format.json do
              render json: {
                message: "Запис про зцілення зафіксовано. Екосистема оновлена.",
                record: @record
              }, status: :created
            end
            format.html { redirect_to api_v1_maintenance_records_path, notice: "Healing ritual recorded." }
          end
        else
          respond_to do |format|
            format.json { render_validation_error(@record) }
            format.html do
              render_dashboard(
                title: "Error in Ritual",
                component: Views::Components::Maintenance::Form.new(record: @record)
              )
            end
          end
        end
      end

      def show
        @record = MaintenanceRecord.find(params[:id])
        respond_to do |format|
          format.json { render json: @record }
          format.html do
            render_dashboard(
              title: "Record Detail // ##{@record.id}",
              component: Views::Components::Maintenance::Show.new(record: @record)
            )
          end
        end
      end

      private

      def maintenance_params
        params.require(:maintenance_record).permit(
          :maintainable_id, :maintainable_type, :ews_alert_id,
          :action_type, :notes, :performed_at
        )
      end
    end
  end
end
