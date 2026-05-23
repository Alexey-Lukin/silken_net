# frozen_string_literal: true

module Api
  module V1
    class ProvisioningController < BaseController
      # [FW.24]: Firmware Soldier має fallback DID (`0x511CEE01`), що використовується
      # коли STM32 unique ID XOR дає 0 (defective UID block). Backend MUST reject
      # таких пристроїв при provisioning, щоб уникнути колізій (два дефектні пристрої
      # отримають однаковий DID `SNET-511CEE01`). Зловмисник також може спробувати
      # зареєструвати "магічний" UID для накладання на легітимні firmware fallback'и.
      # Class-level constant — system-wide invariant tied to firmware behavior.
      FIRMWARE_FALLBACK_DID_MAGIC = "511CEE01"

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
        # [SEC] Normalize hardware_uid ONCE — every downstream check
        # (FW.24 guard, double-init check, DID generation) must operate
        # on the same canonical form. Mixing `.last(8).upcase` (DID path)
        # with `.strip.upcase.last(8)` (guard path) created a bypass:
        # `"  any511CEE01"` passed the FW.24 guard via `.strip` but
        # generated DID `SNET-511CEE01` collision in the firmware fallback space.
        normalized_uid = provisioning_params[:hardware_uid].to_s.strip.upcase
        normalized_suffix = normalized_uid.last(8)

        # [FW.24 GUARD]: Reject hardware_uid whose last 8 hex chars match
        # firmware DID fallback magic (`FIRMWARE_FALLBACK_DID_MAGIC`).
        # DID is generated as `"SNET-#{normalized_uid.last(8)}"`, so any UID
        # ending in `511CEE01` would produce the firmware fallback DID.
        if normalized_suffix == FIRMWARE_FALLBACK_DID_MAGIC
          render json: {
            error: I18n.t("flash.provisioning.fallback_magic_rejected",
                          magic: FIRMWARE_FALLBACK_DID_MAGIC,
                          detail: I18n.t("flash.provisioning.defective_uid"))
          }, status: :unprocessable_content
          return
        end

        # [ЗАХИСТ ВІД ПОДВІЙНОЇ ІНІЦІАЦІЇ]: hardware_uid already provisioned?
        if HardwareKey.exists?(device_uid: normalized_uid)
          render json: { error: I18n.t("flash.provisioning.uid_taken", uid: normalized_uid) }, status: :conflict
          return
        end

        ActiveRecord::Base.transaction do
          @device = build_device(provisioning_params)

          if @device.is_a?(Tree)
            @device.did ||= "SNET-#{normalized_suffix}"
            device_identifier = @device.did
          else
            device_identifier = @device.uid
          end

          if @device.save
            # КРИПТОГРАФІЧНА ПРОПИСКА
            # [SEC.11] HardwareKeyService.provision derives both the AES
            # key and the Lorenz K_seed in one call — single source of
            # truth for "create HardwareKey at provisioning time".
            HardwareKeyService.provision(@device)

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
              notes: I18n.t("flash.provisioning.node_initiated", did: device_identifier, uid: provisioning_params[:hardware_uid]),
              skip_photo_validation: true
            )

            # РЕЄСТРАЦІЯ PEAQ DID (Machine Identity)
            PeaqRegistrationWorker.perform_async(@device.id) if @device.is_a?(Tree)

            respond_to do |format|
              format.json do
                # [P0 BLOCKER FIX] [SEC.11] Neither the AES key nor the
                # Lorenz K_seed is ever returned over the network. Both
                # backend and firmware derive them independently via HKDF
                # from PROVISIONING_MASTER_KEY. Response carries only the
                # DID and a derivation marker.
                render json: {
                  did: device_identifier,
                  device: @device.as_json(only: [ :id, :did, :status, :cluster_id ]),
                  key_derivation: "hkdf-sha256"
                }, status: :created
              end
              format.html do
                # [SEC.11] HKDF derivation is the only mode — UI never
                # sees the raw AES key.
                render_dashboard(
                  title: "Initiation Successful",
                  component: Provisioning::Success.new(device: @device, aes_key: nil)
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
        Rails.logger.error "🚨 [Provisioning] Збій ініціації: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}"
        render json: { error: I18n.t("errors.api.internal") }, status: :internal_server_error
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
