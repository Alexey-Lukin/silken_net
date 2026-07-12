# frozen_string_literal: true

module Api
  module V1
    class FirmwaresController < BaseController
      # Тільки Адміни мають право втручатися в еволюцію коду
      before_action :authorize_admin!

      # Максимальний розмір прошивки (20 МБ) для захисту від перевантаження RAM
      MAX_FIRMWARE_SIZE = 20.megabytes
      # Hex-encoded payload guard: 20 MB binary == 40 MB hex string.
      # Without this an attacker bypassing the file upload could POST
      # bytecode_payload directly and exhaust RAM/disk.
      MAX_BYTECODE_PAYLOAD_HEX_SIZE = 2 * MAX_FIRMWARE_SIZE

      # Allow-list of canonical target hardware classes — matches both
      # OtaTransmissionWorker dispatch and the docs (04_03 §5.7).
      DEPLOY_TARGET_TYPES = %w[Tree Gateway].freeze

      # --- РЕЄСТР ЕВОЛЮЦІЙ (The Evolution Hub) ---
      # GET /api/v1/firmwares
      def index
        @pagy, @firmwares = pagy(BioContractFirmware.order(version: :desc))

        # Збираємо статистику інвентаря для дашборду (org-scoped)
        org = current_user.organization
        @inventory_stats = {
          trees: org.trees.group(:firmware_version).count,
          gateways: org.gateways.group(:firmware_version).count
        }

        respond_to do |format|
          # API Response
          format.json do
            render json: {
              data: @firmwares.as_json(
                only: [ :id, :version, :target_hardware_type, :created_at, :binary_sha256 ],
                methods: [ :deployment_count ]
              ),
              pagy: pagy_metadata(@pagy)
            }
          end

          # Dashboard Response (Phlex)
          format.html do
            render_dashboard(
              title: "Firmware Evolution",
              component: Firmwares::Index.new(
                firmwares: @firmwares,
                inventory_stats: @inventory_stats,
                pagy: @pagy
              )
            )
          end
        end
      end

      # --- ПОРТАЛ ЗАВАНТАЖЕННЯ (The Gateway to New Intellect) ---
      # GET /api/v1/firmwares/new
      def new
        @firmware = BioContractFirmware.new

        render_dashboard(
          title: "Upload New Evolution",
          component: Firmwares::New.new(firmware: @firmware)
        )
      end

      # --- ЗАВАНТАЖЕННЯ НОВОГО ІНТЕЛЕКТУ ---
      # POST /api/v1/firmwares
      def create
        @firmware = BioContractFirmware.new(firmware_params.except(:binary_file, :bytecode_payload))

        # [ЗАХИСТ ПАМ'ЯТІ]: Обмежуємо розмір файлу перед завантаженням у RAM
        if params[:firmware][:binary_file].present?
          uploaded_file = params[:firmware][:binary_file]
          if uploaded_file.size > MAX_FIRMWARE_SIZE
            render json: { error: I18n.t("flash.firmwares.file_too_large", limit: MAX_FIRMWARE_SIZE / 1.megabyte) }, status: :unprocessable_content
            return
          end

          binary_data = uploaded_file.read
          @firmware.bytecode_payload = binary_data.unpack1("H*").upcase
        elsif params[:firmware][:bytecode_payload].present?
          # [SIZE BYPASS FIX]: Without this branch a client could skip the
          # multipart upload (and its MAX_FIRMWARE_SIZE check) by submitting
          # `firmware[bytecode_payload]` directly. Hex is 2× the binary size,
          # so cap accordingly. We also assign through the typed setter rather
          # than mass-assignment so the value goes through model validations.
          hex_payload = params[:firmware][:bytecode_payload].to_s
          if hex_payload.bytesize > MAX_BYTECODE_PAYLOAD_HEX_SIZE
            render json: { error: I18n.t("flash.firmwares.file_too_large", limit: MAX_FIRMWARE_SIZE / 1.megabyte) }, status: :unprocessable_content
            return
          end
          @firmware.bytecode_payload = hex_payload
        end

        if @firmware.save
          respond_to do |format|
            format.json do
              render json: {
                message: I18n.t("flash.firmwares.uploaded", version: @firmware.version),
                firmware: @firmware
              }, status: :created
            end
            format.html { redirect_to api_v1_firmwares_path, notice: I18n.t("flash.firmwares.uploaded", version: @firmware.version) }
          end
        else
          respond_to do |format|
            format.json { render_validation_error(@firmware) }
            format.html do
              render_dashboard(
                title: "Evolution Error",
                component: Firmwares::New.new(firmware: @firmware)
              )
            end
          end
        end
      end

      # --- ПРОВЕРКА ІНВЕНТАРЯ (Who has what?) ---
      # GET /api/v1/firmwares/inventory
      def inventory
        org = current_user.organization
        stats = {
          trees: org.trees.group(:firmware_version).count,
          gateways: org.gateways.group(:firmware_version).count
        }
        render json: stats
      end

      # --- НАКАЗ НА ОНОВЛЕННЯ (The Deployment) ---
      # POST /api/v1/firmwares/:id/deploy
      # Параметри: { cluster_id: 5, target_type: 'Tree', canary_percentage: 1 }
      # canary_percentage (0–100): відсоток шлюзів КОЖНОГО кластера для Canary
      # Deployment. Якщо не вказано — оновлення піде на ВСІ пристрої (100%).
      # Fan-out per-gateway + anti-rollback guard живуть у
      # Ota::DeploymentDispatcherService (SEC.20 Rails-half).
      def deploy
        @firmware = BioContractFirmware.find(params[:id])
        canary_percentage = params[:canary_percentage].present? ? params[:canary_percentage].to_i.clamp(1, 100) : 100

        # [INPUT GUARD]: target_type must be on the allow-list — otherwise an
        # arbitrary string reaches the dispatcher and dies without client feedback.
        target_type = params[:target_type].presence
        if target_type && !DEPLOY_TARGET_TYPES.include?(target_type)
          render json: {
            error: I18n.t("flash.firmwares.invalid_target_type", allowed: DEPLOY_TARGET_TYPES.join(", "))
          }, status: :bad_request
          return
        end

        # [HUMAN-ERROR GUARD]: деплой Tree-контракту з target_type=Gateway (чи
        # навпаки) — ознака плутанини оператора, не легітимний запит.
        if target_type && @firmware.target_hardware_type.present? && target_type != @firmware.target_hardware_type
          render json: {
            error: I18n.t("flash.firmwares.target_type_mismatch", expected: @firmware.target_hardware_type)
          }, status: :bad_request
          return
        end

        # [TENANT-ISOLATION]: cluster_id must belong to the caller's organization.
        # The dispatcher re-scopes through organization.clusters as well —
        # belt-and-suspenders on the cross-tenant OTA vector.
        cluster_id = params[:cluster_id].presence
        if cluster_id && !current_user.organization.clusters.exists?(id: cluster_id)
          render json: { error: I18n.t("errors.api.not_found", model: "Cluster") }, status: :not_found
          return
        end

        result = Ota::DeploymentDispatcherService.call(
          firmware: @firmware,
          organization: current_user.organization,
          cluster_id: cluster_id,
          canary_percentage: canary_percentage
        )

        if result.dispatched?
          respond_to do |format|
            format.json do
              render json: {
                message: I18n.t("flash.firmwares.deployment_dispatched", version: @firmware.version),
                target: cluster_id ? I18n.t("flash.firmwares.target_cluster", id: cluster_id) : I18n.t("flash.firmwares.target_all"),
                canary_percentage: canary_percentage,
                dispatched_gateways: result.dispatched_gateways,
                skipped_clusters: skipped_clusters_json(result)
              }, status: :accepted
            end
            format.html do
              redirect_to api_v1_firmwares_path, notice: I18n.t("flash.firmwares.deployment_dispatched", version: @firmware.version)
            end
          end
        else
          # Нічого не затаргечено: oversized-гейт [FW.60] / anti-rollback / нема цілей.
          reason_key =
            if result.skipped_clusters.any? { |sc| sc.reason == "oversized_firmware" }
              "deployment_oversized"
            elsif result.skipped_clusters.any? { |sc| sc.reason == "rollback" }
              "deployment_rejected_stale"
            else
              "deployment_no_targets"
            end
          respond_to do |format|
            format.json do
              render json: {
                error: I18n.t("flash.firmwares.#{reason_key}"),
                skipped_clusters: skipped_clusters_json(result)
              }, status: :unprocessable_content
            end
            format.html do
              redirect_to api_v1_firmwares_path, alert: I18n.t("flash.firmwares.#{reason_key}")
            end
          end
        end
      end

      private

      def skipped_clusters_json(result)
        result.skipped_clusters.map { |sc| { id: sc.id, name: sc.name, reason: sc.reason } }
      end

      def firmware_params
        params.require(:firmware).permit(:version, :binary_file, :target_hardware, :notes, :target_hardware_type, :tree_family_id, :bytecode_payload)
      end
    end
  end
end
