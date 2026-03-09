# frozen_string_literal: true

module Api
  module V1
    class ProvisioningController < BaseController
      before_action :authorize_forester!

      # --- ТЕРМІНАЛ ІНІЦІАЦІЇ ---
      def new
        @clusters = current_user.organization.clusters
        @families = TreeFamily.all

        render_dashboard(
          title: "Hardware Initiation Ritual",
          component: Provisioning::New.new(
            clusters: @clusters,
            families: @families
          )
        )
      end

      # --- РИТУАЛ ПРИВ'ЯЗКИ ---
      def register
        uid = provisioning_params[:hardware_uid]

        # [ЗАХИСТ ВІД ПОДВІЙНОЇ ІНІЦІАЦІЇ]: Перевіряємо чи hardware_uid вже зареєстрований
        if HardwareKey.exists?(device_uid: uid.to_s.strip.upcase)
          render json: { error: "Пристрій з UID #{uid} вже зареєстрований в системі." }, status: :conflict
          return
        end

        ActiveRecord::Base.transaction do
          @device = build_device(provisioning_params)

          if @device.is_a?(Tree)
            @device.did ||= "SNET-#{provisioning_params[:hardware_uid].last(8).upcase}"
            device_identifier = @device.did
          else
            device_identifier = @device.uid
          end

          if @device.save
            # КРИПТОГРАФІЧНА ПРОПИСКА
            @key_hex = HardwareKeyService.provision(@device)

            # ФІКСАЦІЯ МОНТАЖУ
            MaintenanceRecord.create!(
              maintainable: @device,
              user: current_user,
              action_type: :installation,
              performed_at: Time.current,
              notes: "Ініціація вузла завершена. DID: #{device_identifier}. Hardware UID: #{provisioning_params[:hardware_uid]}",
              skip_photo_validation: true
            )

            respond_to do |format|
              format.json do
                render json: { did: device_identifier, aes_key: @key_hex, device: @device }, status: :created
              end
              format.html do
                # Показуємо результат ритуалу (ключ та DID)
                render_dashboard(
                  title: "Initiation Successful",
                  component: Provisioning::Success.new(device: @device, aes_key: @key_hex)
                )
              end
            end
          else
            respond_to do |format|
              format.json { render_validation_error(@device) }
              format.html { render_new_with_errors }
            end
          end
        end
      rescue StandardError => e
        render json: { error: "Збій ініціації: #{e.message}" }, status: :internal_server_error
      end

      private

      def render_new_with_errors
        @clusters = current_user.organization.clusters
        @families = TreeFamily.all
        render_dashboard(
          title: "Initiation Failed",
          component: Provisioning::New.new(
            clusters: @clusters,
            families: @families,
            device: @device
          )
        )
      end

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
            uid: params[:hardware_uid],
            latitude: params[:latitude],
            longitude: params[:longitude],
            config_sleep_interval_s: 3600
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
