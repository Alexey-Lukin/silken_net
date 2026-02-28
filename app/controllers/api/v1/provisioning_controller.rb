# frozen_string_literal: true

module Api
  module V1
    class ProvisioningController < BaseController
      # Тільки авторизовані Патрульні можуть проводити ініціацію вузлів
      before_action :authorize_forester!

      # --- РИТУАЛ ПРИВ'ЯЗКИ (Hardware-to-DID Binding) ---
      # POST /api/v1/provisioning/register
      # Очікує: hardware_uid (crystal ID), device_type (tree/gateway), cluster_id
      def register
        ActiveRecord::Base.transaction do
          # 1. Визначаємо сутність (Солдат або Королева)
          @device = build_device(provisioning_params)

          # 2. Генеруємо DID на основі hardware_uid (якщо не передано)
          @device.did ||= "SNET-#{provisioning_params[:hardware_uid].last(8).upcase}"

          if @device.save
            # 3. КРИПТОГРАФІЧНА ПРОПИСКА
            # Використовуємо сервіс для створення HardwareKey (Zero-Trust якір)
            # [СИНХРОНІЗОВАНО]: Передаємо hardware_uid як device_uid для ключа
            key_hex = HardwareKeyService.provision(@device)

            # 4. ФІКСАЦІЯ МОНТАЖУ (MaintenanceRecord)
            # Кожен монтаж — це перший запис у журналі зцілення
            MaintenanceRecord.create!(
              maintainable: @device,
              user: current_user,
              action_type: :installation,
              performed_at: Time.current,
              notes: "Ініціація вузла завершена. DID: #{@device.did}. Hardware UID: #{provisioning_params[:hardware_uid]}"
            )

            render json: {
              message: "Вузол успішно інтегрований у міцелій лісу.",
              did: @device.did,
              aes_key: key_hex, # Передаємо Патрульному для фінальної перевірки зв'язку
              device: @device
            }, status: :created
          else
            render_validation_error(@device)
          end
        end
      rescue StandardError => e
        render json: { error: "Збій ініціації: #{e.message}" }, status: :internal_server_error
      end

      private

      def build_device(params)
        case params[:device_type]
        when "tree"
          Tree.new(
            cluster_id: params[:cluster_id],
            tree_family_id: params[:family_id],
            latitude: params[:latitude],
            longitude: params[:longitude]
          )
        when "gateway"
          Gateway.new(
            cluster_id: params[:cluster_id],
            uid: params[:hardware_uid], # Для Королеви UID = Hardware ID
            latitude: params[:latitude],
            longitude: params[:longitude],
            config_sleep_interval_s: 3600 # Default Starlink window
          )
        else
          raise "Невідомий тип вузла в матриці"
        end
      end

      def provisioning_params
        params.require(:provisioning).permit(
          :hardware_uid, :device_type, :cluster_id,
          :family_id, :latitude, :longitude
        )
      end
    end
  end
end
