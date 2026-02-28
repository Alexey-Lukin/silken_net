# frozen_string_literal: true

module Api
  module V1
    class FirmwaresController < BaseController
      # Тільки Адміни мають право втручатися в еволюцію коду
      before_action :authorize_admin!

      # --- РЕЄСТР ЕВОЛЮЦІЙ (The Evolution Hub) ---
      # GET /api/v1/firmwares
      def index
        @firmwares = BioContractFirmware.order(version: :desc)
        
        # Збираємо статистику інвентаря для дашборду
        @inventory_stats = {
          trees: Tree.group(:firmware_version).count,
          gateways: Gateway.group(:firmware_version).count
        }

        respond_to do |format|
          # API Response
          format.json do
            render json: @firmwares.as_json(
              only: [ :id, :version, :target_hardware, :file_size, :created_at, :checksum ],
              methods: [ :deployment_count ]
            )
          end

          # Dashboard Response (Phlex)
          format.html do
            render_dashboard(
              title: "Firmware Evolution",
              component: Views::Components::Firmwares::Index.new(
                firmwares: @firmwares,
                inventory_stats: @inventory_stats
              )
            )
          end
        end
      end

      # --- ЗАВАНТАЖЕННЯ НОВОГО ІНТЕЛЕКТУ ---
      # POST /api/v1/firmwares
      def create
        @firmware = BioContractFirmware.new(firmware_params)

        if @firmware.save
          respond_to do |format|
            format.json do
              render json: {
                message: "Нову еволюцію v#{@firmware.version} завантажено в Океан.",
                firmware: @firmware
              }, status: :created
            end
            format.html { redirect_to api_v1_firmwares_path, notice: "Evolution v#{@firmware.version} uploaded successfully." }
          end
        else
          respond_to do |format|
            format.json { render_validation_error(@firmware) }
            format.html do
              # Якщо помилка, повертаємось на індекс з алертами
              redirect_to api_v1_firmwares_path, alert: @firmware.errors.full_messages.join(", ")
            end
          end
        end
      end

      # --- ПРОВЕРКА ІНВЕНТАРЯ (Who has what?) ---
      # GET /api/v1/firmwares/inventory
      def inventory
        stats = {
          trees: Tree.group(:firmware_version).count,
          gateways: Gateway.group(:firmware_version).count
        }
        render json: stats
      end

      # --- НАКАЗ НА ОНОВЛЕННЯ (The Deployment) ---
      # POST /api/v1/firmwares/:id/deploy
      # Параметри: { cluster_id: 5 } або { target_type: 'Tree' }
      def deploy
        @firmware = BioContractFirmware.find(params[:id])

        # Запускаємо масове оновлення через Sidekiq
        # [СИНХРОНІЗОВАНО]: OtaTransmissionWorker обробить чергу завантажень
        OtaTransmissionWorker.perform_async(
          @firmware.id,
          params[:cluster_id],
          params[:target_type]
        )

        respond_to do |format|
          format.json do
            render json: {
              message: "Наказ на еволюцію v#{@firmware.version} відправлено в ефір.",
              target: params[:cluster_id] ? "Кластер ##{params[:cluster_id]}" : "Весь ліс"
            }, status: :accepted
          end
          format.html do
            redirect_to api_v1_firmwares_path, notice: "Evolution deployment initiated for v#{@firmware.version}."
          end
        end
      end

      private

      def firmware_params
        params.require(:firmware).permit(:version, :binary_file, :target_hardware, :notes)
      end
    end
  end
end
