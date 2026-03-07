# frozen_string_literal: true

module Api
  module V1
    class MaintenanceRecordsController < BaseController
      before_action :authorize_forester!
      before_action :set_record, only: [ :show, :update, :verify, :photos ]

      # --- ЖУРНАЛ ВТРУЧАНЬ ---
      def index
        @records = organization_scoped_records
                     .includes(:user, :maintainable, photos_attachments: :blob)
                     .order(performed_at: :desc)

        if params[:maintainable_type].present? && params[:maintainable_id].present?
          @records = @records.where(
            maintainable_type: params[:maintainable_type],
            maintainable_id: params[:maintainable_id]
          )
        end

        @records = @records.where(action_type: params[:action_type]) if params[:action_type].present?
        @records = @records.hardware_verified if params[:verified].present?
        @records = @records.where("performed_at >= ?", params[:from]) if params[:from].present?
        @records = @records.where("performed_at <= ?", params[:to]) if params[:to].present?

        @pagy, @records = pagy(@records, items: 50)

        respond_to do |format|
          format.json do
            render json: {
              records: MaintenanceRecordBlueprint.render_as_hash(@records, view: :index),
              pagy: { page: @pagy.page, limit: @pagy.limit, count: @pagy.count, pages: @pagy.last }
            }
          end
          format.html do
            render_dashboard(
              title: "Maintenance Log // Records of Healing",
              component: Maintenance::Index.new(records: @records, pagy: @pagy)
            )
          end
        end
      end

      # --- НОВА ФОРМА ---
      def new
        @record = current_user.maintenance_records.build(
          maintainable_type: params[:maintainable_type] || "Tree",
          maintainable_id: params[:maintainable_id],
          ews_alert_id: params[:ews_alert_id]
        )

        render_dashboard(
          title: "New Maintenance Ritual",
          component: Maintenance::Form.new(record: @record)
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
                record: MaintenanceRecordBlueprint.render_as_hash(@record, view: :show)
              }, status: :created
            end
            format.html { redirect_to api_v1_maintenance_record_path(@record), notice: "Healing ritual recorded." }
          end
        else
          respond_to do |format|
            format.json { render_validation_error(@record) }
            format.html do
              render_dashboard(
                title: "Error in Ritual",
                component: Maintenance::Form.new(record: @record)
              )
            end
          end
        end
      end

      # --- ДЕТАЛІ ЗАПИСУ ---
      def show
        @pagy_photos, @photos = pagy(@record.photos, items: 6)
        respond_to do |format|
          format.json { render json: MaintenanceRecordBlueprint.render_as_hash(@record, view: :show) }
          format.html do
            render_dashboard(
              title: "Record // ##{@record.id}",
              component: Maintenance::Show.new(
                record: @record, photos: @photos, pagy_photos: @pagy_photos
              )
            )
          end
        end
      end

      # --- ПАГІНАЦІЯ ФОТО (Turbo Frame Load More) ---
      # GET /api/v1/maintenance_records/:id/photos?page=N
      def photos
        @pagy_photos, @photos = pagy(@record.photos, items: 6)
        render Maintenance::PhotosPage.new(
          record: @record, photos: @photos, pagy: @pagy_photos
        )
      end

      # --- РЕДАГУВАННЯ ЗАПИСУ ---
      def update
        if @record.update(maintenance_params)
          respond_to do |format|
            format.json do
              render json: {
                message: "Запис оновлено.",
                record: MaintenanceRecordBlueprint.render_as_hash(@record, view: :show)
              }
            end
            format.html { redirect_to api_v1_maintenance_record_path(@record), notice: "Record updated." }
          end
        else
          respond_to do |format|
            format.json { render_validation_error(@record) }
            format.html do
              render_dashboard(
                title: "Edit Record // ##{@record.id}",
                component: Maintenance::Form.new(record: @record)
              )
            end
          end
        end
      end

      # --- HARDWARE VERIFY (STM32 підтвердження) ---
      # Патрульний натискає "Verify" у додатку — STM32 відповів новим пульсом.
      def verify
        if @record.update(hardware_verified: true)
          respond_to do |format|
            format.json do
              render json: {
                message: "Hardware state verified. STM32 pulse acknowledged.",
                hardware_verified: true,
                record_id: @record.id
              }
            end
            format.html { redirect_to api_v1_maintenance_record_path(@record), notice: "Hardware verified." }
          end
        else
          render_validation_error(@record)
        end
      end

      private

      def set_record
        @record = organization_scoped_records
                    .includes(photos_attachments: :blob)
                    .find(params[:id])
      end

      # Обмежуємо доступ до записів лише організацією поточного користувача
      def organization_scoped_records
        org_cluster_ids = current_user.organization.clusters.select(:id)

        MaintenanceRecord.where(
          "(maintainable_type = 'Tree' AND maintainable_id IN (?)) OR " \
          "(maintainable_type = 'Gateway' AND maintainable_id IN (?))",
          Tree.where(cluster_id: org_cluster_ids).select(:id),
          Gateway.where(cluster_id: org_cluster_ids).select(:id)
        )
      end

      def maintenance_params
        params.require(:maintenance_record).permit(
          :maintainable_id, :maintainable_type, :ews_alert_id,
          :action_type, :notes, :performed_at,
          :labor_hours, :parts_cost,
          :hardware_verified,
          :latitude, :longitude,
          photos: []
        )
      end
    end
  end
end
