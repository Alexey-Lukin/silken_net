# frozen_string_literal: true

module Api
  module V1
    class FirmwaresController < BaseController
      # Тільки Адміни мають право втручатися в еволюцію коду
      before_action :authorize_admin!

      # --- РЕЄСТР ЕВОЛЮЦІЙ ---
      # GET /api/v1/firmwares
      def index
        @firmwares = Firmware.order(version: :desc)
        render json: @firmwares.as_json(
          only: [:id, :version, :target_hardware, :file_size, :created_at, :checksum],
          methods: [:deployment_count]
        )
      end

      # --- ЗАВАНТАЖЕННЯ НОВОГО ІНТЕЛЕКТУ ---
      # POST /api/v1/firmwares
      def create
        @firmware = Firmware.new(firmware_params)
        
        if @firmware.save
          render json: { 
            message: "Нову еволюцію v#{@firmware.version} завантажено в Океан.",
            firmware: @firmware 
          }, status: :created
        else
          render_validation_error(@firmware)
        end
      end

      # --- ПРОВЕРКА ІНВЕНТАРЯ (Who has what?) ---
      # GET /api/v1/firmwares/inventory
      def inventory
        # Збираємо статистику версій по всьому лісу
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
        @firmware = Firmware.find(params[:id])
        
        # Запускаємо масове оновлення через воркер
        # [СИНХРОНІЗОВАНО]: OtaTransmissionWorker обробить чергу завантажень
        OtaTransmissionWorker.perform_async(
          @firmware.id, 
          params[:cluster_id], 
          params[:target_type]
        )

        render json: { 
          message: "Наказ на еволюцію v#{@firmware.version} відправлено в ефір.",
          target: params[:cluster_id] ? "Кластер ##{params[:cluster_id]}" : "Весь ліс"
        }, status: :accepted
      end

      private

      def firmware_params
        params.require(:firmware).permit(:version, :binary_file, :target_hardware, :notes)
      end
    end
  end
end
