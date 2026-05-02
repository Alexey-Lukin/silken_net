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
        uid = provisioning_params[:hardware_uid]

        # [FW.24 GUARD]: Reject hardware_uid, останні 8 hex символів якого збігаються
        # з firmware DID fallback magic (`FIRMWARE_FALLBACK_DID_MAGIC`, class-level
        # constant). DID генерується як `"SNET-#{uid.last(8).upcase}"`,
        # отже якщо UID закінчується на `511CEE01` — DID буде `SNET-511CEE01` (firmware
        # fallback). Перевірка hex/case-insensitive.
        normalized_suffix = uid.to_s.strip.upcase.last(8)
        if normalized_suffix == FIRMWARE_FALLBACK_DID_MAGIC
          render json: {
            error: "Hardware UID закінчується магічним fallback значенням (#{FIRMWARE_FALLBACK_DID_MAGIC}). " \
                   "Це резервоване firmware значення для defective STM32 UID — реєстрація заборонена. " \
                   "Перепрошийте пристрій та повторно зчитайте unique ID."
          }, status: :unprocessable_content
          return
        end

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
            # [SEC.11] HardwareKeyService.provision derives both the AES
            # key and the Lorenz K_seed in one call — single source of
            # truth for "create HardwareKey at provisioning time".
            @key_hex = HardwareKeyService.provision(@device)
            hw_key = HardwareKey.find_by(device_uid: device_identifier)
            @lorenz_seed_hex = hw_key&.lorenz_seed_hex

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
                response_body = {
                  did: device_identifier,
                  device: @device.as_json(only: [ :id, :did, :status, :cluster_id ]),
                  key_derivation: "hkdf-sha256"
                }

                # TRL 4 lab mode: якщо PROVISIONING_MASTER_KEY не встановлено,
                # повертаємо ключ для ручного прошивання на лабораторному стенді.
                if ENV["PROVISIONING_MASTER_KEY"].blank?
                  response_body[:aes_key] = @key_hex
                  # [SEC.11] Lorenz K_seed mirrors the AES key in lab mode
                  # so the Flash burn-in tool can write both blobs at once.
                  response_body[:lorenz_seed] = @lorenz_seed_hex
                  response_body[:warning] = "TRL4 lab mode: AES key included in response. " \
                                            "Set PROVISIONING_MASTER_KEY for production HKDF derivation."
                end

                render json: response_body, status: :created
              end
              format.html do
                # [A-2 FIX]: В Production HKDF mode ключ не передається до UI-компонента.
                # Zero-Trust: ключ деривується незалежно на прошивці.
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
        Rails.logger.error "🚨 [Provisioning] Збій ініціації: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}"
        render json: { error: "Збій у ядрі Океану. Повідомте Архітектора." }, status: :internal_server_error
      end

      # [SEC.11] Field-migration endpoint. Existing devices provisioned
      # before SEC.11 have an AES key but no `lorenz_seed_hex`. Upon their
      # first uplink post-deploy, the field-ops tool calls this endpoint
      # with the device's DID; backend deterministically re-derives K_seed
      # from `PROVISIONING_MASTER_KEY` (HKDF-SHA256) and persists it on
      # `hardware_keys.lorenz_seed_hex`. Idempotent — re-deriving the same
      # K_seed yields the identical hex. The endpoint is a no-op for
      # devices that already have a seed (`status: ok, upgraded: false`).
      def upgrade_seed
        device_uid = params.require(:hardware_uid).to_s.strip.upcase
        hw_key = HardwareKey.find_by(device_uid: device_uid)

        if hw_key.nil?
          render json: { error: "Hardware key not found for #{device_uid}." },
                 status: :not_found
          return
        end

        if hw_key.lorenz_seed_hex.present?
          render json: {
            did: device_uid,
            upgraded: false,
            key_derivation: "hkdf-sha256",
            note: "K_seed already provisioned — no-op."
          }, status: :ok
          return
        end

        seed_hex = SilkenNet::SeedDerivation.derive_seed(device_uid)
        hw_key.update!(lorenz_seed_hex: seed_hex)

        response_body = {
          did: device_uid,
          upgraded: true,
          key_derivation: "hkdf-sha256"
        }

        # Lab mode: surface the freshly-derived seed so an operator can
        # flash the Soldier Flash sector by hand. In production HKDF
        # mode firmware re-derives the same value independently.
        if ENV["PROVISIONING_MASTER_KEY"].blank?
          response_body[:lorenz_seed] = seed_hex
          response_body[:warning] = "TRL4 lab mode: K_seed included in response. " \
                                    "Set PROVISIONING_MASTER_KEY for production HKDF derivation."
        end

        render json: response_body, status: :ok
      rescue ActionController::ParameterMissing => e
        render json: { error: e.message }, status: :unprocessable_content
      rescue SecurityError => e
        Rails.logger.error "🚨 [Provisioning::UpgradeSeed] #{e.message}"
        render json: { error: e.message }, status: :service_unavailable
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
