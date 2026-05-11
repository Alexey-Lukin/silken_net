# frozen_string_literal: true

module Api
  module V1
    class FirmwaresController < BaseController
      # Тільки Адміни мають право втручатися в еволюцію коду
      before_action :authorize_admin!

      # Максимальний розмір прошивки (20 МБ) для захисту від перевантаження RAM
      MAX_FIRMWARE_SIZE = 20.megabytes

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
        @firmware = BioContractFirmware.new(firmware_params.except(:binary_file))

        # [ЗАХИСТ ПАМ'ЯТІ]: Обмежуємо розмір файлу перед завантаженням у RAM
        if params[:firmware][:binary_file].present?
          uploaded_file = params[:firmware][:binary_file]
          if uploaded_file.size > MAX_FIRMWARE_SIZE
            render json: { error: I18n.t("flash.firmwares.file_too_large", limit: MAX_FIRMWARE_SIZE / 1.megabyte) }, status: :unprocessable_content
            return
          end

          binary_data = uploaded_file.read
          @firmware.bytecode_payload = binary_data.unpack1("H*").upcase
        end

        if @firmware.save
          respond_to do |format|
            format.json do
              render json: {
                message: I18n.t("flash.firmwares.uploaded", version: @firmware.version),
                firmware: @firmware
              }, status: :created
            end
            format.html { redirect_to api_v1_firmwares_path, notice: "Evolution v#{@firmware.version} uploaded successfully." }
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
      # canary_percentage (0–100): відсоток пристроїв для Canary Deployment.
      # Якщо не вказано — оновлення піде на ВСІ пристрої (100%).
      def deploy
        @firmware = BioContractFirmware.find(params[:id])
        canary_percentage = params[:canary_percentage].present? ? params[:canary_percentage].to_i.clamp(1, 100) : 100

        # Запускаємо масове оновлення через Sidekiq
        # [СИНХРОНІЗОВАНО]: OtaTransmissionWorker обробить чергу завантажень
        OtaTransmissionWorker.perform_async(
          @firmware.id,
          params[:cluster_id],
          params[:target_type],
          canary_percentage
        )

        respond_to do |format|
          format.json do
            render json: {
              message: I18n.t("flash.firmwares.deployment_dispatched", version: @firmware.version),
              target: params[:cluster_id] ? I18n.t("flash.firmwares.target_cluster", id: params[:cluster_id]) : I18n.t("flash.firmwares.target_all"),
              canary_percentage: canary_percentage
            }, status: :accepted
          end
          format.html do
            redirect_to api_v1_firmwares_path, notice: "Evolution deployment initiated for v#{@firmware.version} (#{canary_percentage}% canary)."
          end
        end
      end

      private

      def firmware_params
        params.require(:firmware).permit(:version, :binary_file, :target_hardware, :notes, :target_hardware_type, :tree_family_id, :bytecode_payload)
      end
    end
  end
end
