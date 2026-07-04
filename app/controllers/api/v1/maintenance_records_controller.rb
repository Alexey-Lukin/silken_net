# frozen_string_literal: true

module Api
  module V1
    class MaintenanceRecordsController < BaseController
      before_action :authorize_forester!
      before_action :set_record, only: [ :show, :edit, :update, :verify, :photos ]
      before_action :authorize_record_mutation!, only: [ :edit, :update, :verify ]

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

        # [INPUT GUARD]: invalid ISO8601 dates passed to `where("performed_at >= ?")`
        # surface as `PG::InvalidDatetimeFormat` mid-query (HTTP 500). Parse and
        # validate once; if either bound is malformed, fail fast with 400 so the
        # client sees a clear error and Sentry doesn't see the noise.
        if params[:from].present?
          parsed_from = parse_iso8601_filter(params[:from])
          return render(json: { error: I18n.t("flash.maintenance.invalid_date", value: params[:from]) }, status: :bad_request) if parsed_from.nil?
          @records = @records.where("performed_at >= ?", parsed_from)
        end

        if params[:to].present?
          parsed_to = parse_iso8601_filter(params[:to])
          return render(json: { error: I18n.t("flash.maintenance.invalid_date", value: params[:to]) }, status: :bad_request) if parsed_to.nil?
          @records = @records.where("performed_at <= ?", parsed_to)
        end

        @pagy, @records = pagy(@records, items: 50)

        respond_to do |format|
          format.json do
            render json: {
              data: MaintenanceRecordBlueprint.render_as_hash(@records, view: :index),
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
        verify_maintainable_within_organization!(@record)

        if @record.save
          respond_to do |format|
            format.json do
              render json: {
                message: I18n.t("flash.maintenance.record_created"),
                record: MaintenanceRecordBlueprint.render_as_hash(@record, view: :show)
              }, status: :created
            end
            format.html { redirect_to api_v1_maintenance_record_path(@record), notice: I18n.t("flash.maintenance.record_created") }
          end
        else
          respond_to do |format|
            format.json { render_validation_error(@record) }
            format.html do
              render_dashboard(
                title: "Error in Ritual",
                component: Maintenance::Form.new(
                  record: @record,
                  existing_photos: @record.persisted? ? @record.photos.limit(6).to_a : []
                )
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

      # --- ФОРМА РЕДАГУВАННЯ ---
      # GET /api/v1/maintenance_records/:id/edit
      def edit
        render_dashboard(
          title: "Edit Record // ##{@record.id}",
          component: Maintenance::Form.new(
            record: @record,
            existing_photos: @record.photos.limit(6).to_a
          )
        )
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
                message: I18n.t("flash.maintenance.record_updated"),
                record: MaintenanceRecordBlueprint.render_as_hash(@record, view: :show)
              }
            end
            format.html { redirect_to api_v1_maintenance_record_path(@record), notice: I18n.t("flash.maintenance.record_updated") }
          end
        else
          respond_to do |format|
            format.json { render_validation_error(@record) }
            format.html do
              render_dashboard(
                title: "Edit Record // ##{@record.id}",
                component: Maintenance::Form.new(
                  record: @record,
                  existing_photos: @record.photos.limit(6).to_a
                )
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
                message: I18n.t("flash.maintenance.hardware_verified"),
                hardware_verified: true,
                record_id: @record.id
              }
            end
            format.html { redirect_to api_v1_maintenance_record_path(@record), notice: I18n.t("flash.maintenance.hardware_verified") }
          end
        else
          render_validation_error(@record)
        end
      end

      private

      # Returns nil for malformed input; both ISO8601 and date-only ("2026-05-23")
      # strings parse cleanly via Time.iso8601. Returning nil lets the caller
      # produce a 400 instead of leaking a server-side exception.
      def parse_iso8601_filter(raw)
        Time.iso8601(raw.to_s)
      rescue ArgumentError
        nil
      end

      # [AUTHZ FIX]: Forester could edit/verify another forester's maintenance
      # record within the same org — the only check was `authorize_forester!`.
      # Restrict mutations to the author; admin+ keep the override for audit.
      def authorize_record_mutation!
        return if current_user.role_admin? || current_user.role_super_admin?
        return if @record.user_id == current_user.id

        render_forbidden
      end

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

      # [SEC IDOR]: maintainable_id/ews_alert_id надходять клієнтом через
      # mass-assignment — без перевірки форестер org-A подавав би
      # decommissioning/biomass_extraction на дерево org-B (→ EcosystemHealingWorker
      # ретайрить/оголошує мертвим чуже дерево + каскад slashing) або гасив би
      # чужу ews-тривогу. Дзеркало organization_scoped_records, застосоване ДО save.
      def verify_maintainable_within_organization!(record)
        target = record.maintainable
        # Відсутній/неіснуючий maintainable — НЕ security-кейс: хай модельна
        # валідація (`belongs_to :maintainable` required) поверне 422, не 404.
        # Гард ловить лише ІСНУЮЧИЙ-але-чужий maintainable (cross-tenant IDOR).
        return if target.nil?

        owned =
          case target
          when Tree, Gateway
            current_user.organization.clusters.exists?(id: target.cluster_id)
          else
            false
          end
        raise ActiveRecord::RecordNotFound unless owned

        if record.ews_alert_id.present? &&
           !current_user.organization.ews_alerts.exists?(id: record.ews_alert_id)
          raise ActiveRecord::RecordNotFound
        end
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
