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
        # [SEC] Normalize hardware_uid ONCE — every downstream check
        # (double-init check, DID derivation) must operate on the same
        # canonical form (історичний bypass: `.strip` в одному шляху і ні —
        # в іншому).
        normalized_uid = provisioning_params[:hardware_uid].to_s.strip.upcase

        # [FW.54] Tree: hardware_uid = 24-hex кремнієвий UID (три %08X-слова,
        # порядок регістрів 0x1FFF7590/94/98) → DID деривується murmur3-fmix32
        # (03_01 §7) — той самий, що плата порахує собі на boot. До FW.54 тут
        # стояв `last(8)`-суфікс: кожне UI-дерево отримувало DID, якого його
        # кремній ніколи не оголосить. Gateway: uid як введено (SNET-Q-…).
        tree_did = nil
        if provisioning_params[:device_type] == "tree"
          begin
            tree_did = SilkenNet::DidDerivation.wire_did_from_uid_hex(normalized_uid)
          rescue ArgumentError
            render json: { error: I18n.t("flash.provisioning.invalid_uid", uid: normalized_uid) },
                   status: :unprocessable_content
            return
          end
        end

        # [ЗАХИСТ ВІД ПОДВІЙНОЇ ІНІЦІАЦІЇ]: перевіряємо той ідентифікатор, під
        # яким provision реально пише HardwareKey (Tree → derived DID; Gateway
        # → uid). До FW.54 тут стояв сирий hardware_uid — для дерев guard був
        # мертвий (provision зберігає "SNET-…", не 24-hex вхід).
        guard_identifier = tree_did || normalized_uid
        if HardwareKey.exists?(device_uid: guard_identifier)
          render json: { error: I18n.t("flash.provisioning.uid_taken", uid: guard_identifier) }, status: :conflict
          return
        end

        # [SEC IDOR]: cluster_id надходить від клієнта — переконуємось, що він
        # належить організації форестера (дзеркало firmwares#deploy /
        # oracle_visions#simulate, які цей клас багу вже закрили). Без цього
        # форестер org-A провізіонить пристрій + HardwareKey + DID у кластер org-B.
        unless current_user.organization.clusters.exists?(id: provisioning_params[:cluster_id])
          render json: { error: I18n.t("errors.api.not_found", model: "Cluster") }, status: :not_found
          return
        end

        ActiveRecord::Base.transaction do
          @device = build_device(provisioning_params)

          if @device.is_a?(Tree)
            @device.did             = tree_did
            @device.silicon_uid_hex = normalized_uid
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
        # `e.backtrace` is always populated here — `e` reached this rescue via an
        # actual `raise`, and `Api::V1::BaseController#render_internal_server_error`
        # (the same StandardError net, wider scope) already calls `.first(5).join`
        # with no safe-nav — mirrored here for consistency.
        Rails.logger.error "🚨 [Provisioning] Збій ініціації: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
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
