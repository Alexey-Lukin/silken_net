# frozen_string_literal: true

module Api
  module V1
    class ProvisioningController < BaseController
      before_action :authorize_forester!

      # --- ТЕРМІНАЛ ІНІЦІАЦІЇ ---
      def new
        @clusters = current_user.organization.clusters
        # [ВИПРАВЛЕНО: Unbounded Query]: Використовуємо alphabetical скоуп замість .all.
        # TreeFamily — довідник видів (~100-1000 записів), але .all не має ORDER BY
        # та не обмежує вибірку. alphabetical забезпечує детермінований порядок.
        @families = TreeFamily.alphabetical

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

            # [M2M Auth]: Реєструємо Ed25519 public key для M2M автентифікації шлюзу
            if provisioning_params[:ed25519_public_key].present?
              hw_key = HardwareKey.find_by!(device_uid: device_identifier)
              hw_key.update!(ed25519_public_key_hex: provisioning_params[:ed25519_public_key])
            end

            # ФІКСАЦІЯ МОНТАЖУ
            MaintenanceRecord.create!(
              maintainable: @device,
              user: current_user,
              action_type: :installation,
              performed_at: Time.current,
              notes: "Ініціація вузла завершена. DID: #{device_identifier}. Hardware UID: #{provisioning_params[:hardware_uid]}",
              skip_photo_validation: true
            )

            # РЕЄСТРАЦІЯ PEAQ DID (Machine Identity)
            PeaqRegistrationWorker.perform_async(@device.id) if @device.is_a?(Tree)

            respond_to do |format|
              format.json do
                # [P0 BLOCKER FIX]: AES ключ НЕ передається через мережу.
                # Обидві сторони (бекенд + прошивка) деривують ключ незалежно через HKDF.
                # Повертаємо лише DID та підтвердження провізіонування.
                response_body = { did: device_identifier, device: @device, key_derivation: "hkdf-sha256" }

                # TRL 4 lab mode: якщо PROVISIONING_MASTER_KEY не встановлено,
                # повертаємо ключ для ручного прошивання на лабораторному стенді.
                if ENV["PROVISIONING_MASTER_KEY"].blank?
                  response_body[:aes_key] = @key_hex
                  response_body[:warning] = "TRL4 lab mode: AES key included in response. " \
                                            "Set PROVISIONING_MASTER_KEY for production HKDF derivation."
                end

                render json: response_body, status: :created
              end
              format.html do
                # [A-2 FIX]: В Production HKDF mode ключ не передається до UI-компонента.
                # Zero-Trust: ключ деривується незалежно на прошивці.
                # У TRL4 lab mode (PROVISIONING_MASTER_KEY не встановлено) — передаємо для ручного прошивання.
                display_key = ENV["PROVISIONING_MASTER_KEY"].blank? ? @key_hex : nil
                render_dashboard(
                  title: "Initiation Successful",
                  component: Provisioning::Success.new(device: @device, aes_key: display_key)
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
        @families = TreeFamily.alphabetical
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
          :family_id, :latitude, :longitude, :ed25519_public_key
        )
      end
    end
  end
end
