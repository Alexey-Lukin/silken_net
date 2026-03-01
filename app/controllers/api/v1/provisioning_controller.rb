# frozen_string_literal: true

module Api
  module V1
    class ProvisioningController < BaseController
      before_action :authorize_forester!

      # --- ТЕРМІНАЛ ІНІЦІАЦІЇ ---
      def new
        @clusters = Cluster.all
        @families = TreeFamily.all

        render_dashboard(
          title: "Hardware Initiation Ritual",
          component: Views::Components::Provisioning::New.new(
            clusters: @clusters,
            families: @families
          )
        )
      end

      # --- РИТУАЛ ПРИВ'ЯЗКИ ---
      def register
        ActiveRecord::Base.transaction do
          @device = build_device(provisioning_params)
          @device.did ||= "SNET-#{provisioning_params[:hardware_uid].last(8).upcase}"

          if @device.save
            # КРИПТОГРАФІЧНА ПРОПИСКА
            @key_hex = HardwareKeyService.provision(@device)

            # ФІКСАЦІЯ МОНТАЖУ
            MaintenanceRecord.create!(
              maintainable: @device,
              user: current_user,
              action_type: :installation,
              performed_at: Time.current,
              notes: "Ініціація вузла завершена. DID: #{@device.did}. Hardware UID: #{provisioning_params[:hardware_uid]}"
            )

            respond_to do |format|
              format.json do
                render json: { did: @device.did, aes_key: @key_hex, device: @device }, status: :created
              end
              format.html do
                # Показуємо результат ритуалу (ключ та DID)
                render_dashboard(
                  title: "Initiation Successful",
                  component: Views::Components::Provisioning::Success.new(device: @device, aes_key: @key_hex)
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
        @clusters = Cluster.all
        @families = TreeFamily.all
        render_dashboard(
          title: "Initiation Failed",
          component: Views::Components::Provisioning::New.new(
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
