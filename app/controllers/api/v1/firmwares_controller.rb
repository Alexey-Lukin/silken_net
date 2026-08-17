# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Api
  module V1
    class FirmwaresController < BaseController
      # Тільки Адміни мають право втручатися в еволюцію коду
      before_action :authorize_admin!

      # Максимальний розмір прошивки (20 МБ) для захисту від перевантаження RAM
      MAX_FIRMWARE_SIZE = 20.megabytes
      # Hex-encoded payload guard: 20 MB binary == 40 MB hex string.
      # Without this an attacker bypassing the file upload could POST
      # bytecode_payload directly and exhaust RAM/disk.
      MAX_BYTECODE_PAYLOAD_HEX_SIZE = 2 * MAX_FIRMWARE_SIZE

      # Allow-list of canonical target hardware classes — matches both
      # OtaTransmissionWorker dispatch and the docs (04_03 §5.7).
      DEPLOY_TARGET_TYPES = %w[Tree Gateway].freeze

      # --- РЕЄСТР ЕВОЛЮЦІЙ (The Evolution Hub) ---
      # GET /firmwares
      def index
        @pagy, @firmwares = pagy(BioContractFirmware.order(version: :desc))

        # [ARCH.83] Каталог образів тенанта НЕ має за побудовою (`04_03 §3.1`), тож
        # рендериться й ДО вибору клану. Доти тут стояв `acting_organization!` — банг
        # заради самої лише декоративної половини нижче, — і платформений адмін
        # (обидва сіджені super_admin створюються без організації) не бачив реєстру
        # прошивок узагалі, доки не всиновить випадкового тенанта.
        org = acting_organization

        # ⚠️ `nil`, а НЕ `{}`: порожній хеш друкується як «нуль пристроїв на кожній
        # версії», тобто вигаданий вимір на місці невиміряного [ARCH.84]. Розрізняти
        # «контексту немає» від «пристроїв немає» — робота компонента.
        @inventory_stats = firmware_inventory_for(org) if org

        # [SEC.20] Живі OTA-кампанії: updating АБО затаргечені (Queen ще
        # не поллила hint) — прогрес-бари з підпискою на Firmwares::Index.
        # Без контексту секція просто відсутня: мовчання не є твердженням, тоді як
        # «0 кампаній» ним було б.
        @active_ota_gateways =
          if org
            org.gateways.where(state: :updating)
               .or(org.gateways.where.not(pending_firmware_id: nil))
               .order(:uid).to_a
          else
            []
          end

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
              title: I18n.t("firmwares.index_title"),
              component: Firmwares::Index.new(
                firmwares: @firmwares,
                inventory_stats: @inventory_stats,
                pagy: @pagy,
                active_ota_gateways: @active_ota_gateways
              )
            )
          end
        end
      end

      # --- ПОРТАЛ ЗАВАНТАЖЕННЯ (The Gateway to New Intellect) ---
      # GET /firmwares/new
      def new
        @firmware = BioContractFirmware.new

        render_dashboard(
          title: I18n.t("firmwares.new_title"),
          component: Firmwares::New.new(firmware: @firmware)
        )
      end

      # --- ЗАВАНТАЖЕННЯ НОВОГО ІНТЕЛЕКТУ ---
      # POST /firmwares
      def create
        @firmware = BioContractFirmware.new(firmware_params.except(:binary_file, :bytecode_payload))

        # [ЗАХИСТ ПАМ'ЯТІ]: Обмежуємо розмір файлу перед завантаженням у RAM
        if params[:firmware][:binary_file].present?
          uploaded_file = params[:firmware][:binary_file]
          if uploaded_file.size > MAX_FIRMWARE_SIZE
            render_oversized_upload
            return
          end

          binary_data = uploaded_file.read
          @firmware.bytecode_payload = binary_data.unpack1("H*").upcase
        elsif params[:firmware][:bytecode_payload].present?
          # [SIZE BYPASS FIX]: Without this branch a client could skip the
          # multipart upload (and its MAX_FIRMWARE_SIZE check) by submitting
          # `firmware[bytecode_payload]` directly. Hex is 2× the binary size,
          # so cap accordingly. We also assign through the typed setter rather
          # than mass-assignment so the value goes through model validations.
          hex_payload = params[:firmware][:bytecode_payload].to_s
          if hex_payload.bytesize > MAX_BYTECODE_PAYLOAD_HEX_SIZE
            # ⚠️ [SEC.25 Ф4] Ця гілка свідомо лишається JSON-only, на відміну від
            # сусідньої: поля `bytecode_payload` у формі НЕМАЄ — вона рендерить лише
            # version/target_hardware_type/binary_file, — тож браузер сюди не доходить
            # у принципі, і HTML-гілка була б мертвим кодом із дня написання. Це
            # API-обхід multipart-ліміту, і він API-шляхом і лишається.
            render json: { error: I18n.t("flash.firmwares.file_too_large", limit: MAX_FIRMWARE_SIZE / 1.megabyte) }, status: :unprocessable_content
            return
          end
          @firmware.bytecode_payload = hex_payload
        end

        if @firmware.save
          respond_to do |format|
            format.json do
              # `only:` несучий: голий `@firmware` серіалізує ВСІ колонки, тобто
              # повертає завантажений `bytecode_payload` (до 40 МБ hex) назад клієнту.
              # Набір дзеркалить `index` і контракт `04_03 §5.8`.
              render json: {
                message: I18n.t("flash.firmwares.uploaded", version: @firmware.version),
                firmware: @firmware.as_json(only: [ :id, :version, :target_hardware_type, :binary_sha256, :created_at ])
              }, status: :created
            end
            format.html { redirect_to firmwares_path, success: I18n.t("flash.firmwares.uploaded", version: @firmware.version) }
          end
        else
          respond_to do |format|
            format.json { render_validation_error(@firmware) }
            # [SEC.25] Дзеркалить статус JSON-гілки — на `200` без редиректу Turbo
            # відповідь викидає, тобто відхилений upload прошивки не показував
            # оператору нічого.
            format.html do
              render_dashboard(
                title: I18n.t("firmwares.create_error_title"),
                component: Firmwares::New.new(firmware: @firmware),
                status: :unprocessable_content
              )
            end
          end
        end
      end

      # --- ПРОВЕРКА ІНВЕНТАРЯ (Who has what?) ---
      # GET /firmwares/inventory
      # ⊥ [ARCH.83] Банг тут ПРАВИЛЬНИЙ і лишається: на відміну від каталогу в `index`,
      # цей екшен віддає виключно org-скоуплені дані, тобто ресурс тенантний — і на
      # нього діє інша, теж ратифікована політика (однакове 422, `contracts#stats`:
      # «не втрата, а вирівнювання»). Межу стереже request-пін.
      def inventory
        render json: firmware_inventory_for(acting_organization!)
      end

      # --- НАКАЗ НА ОНОВЛЕННЯ (The Deployment) ---
      # POST /firmwares/:id/deploy
      # Параметри: { cluster_id: 5, target_type: 'Tree', canary_percentage: 1 }
      # canary_percentage (0–100): відсоток шлюзів КОЖНОГО кластера для Canary
      # Deployment. Якщо не вказано — оновлення піде на ВСІ пристрої (100%).
      # Fan-out per-gateway + anti-rollback guard живуть у
      # Ota::DeploymentDispatcherService (SEC.20 Rails-half).
      def deploy
        @firmware = BioContractFirmware.find(params[:id])
        canary_percentage = params[:canary_percentage].present? ? params[:canary_percentage].to_i.clamp(1, 100) : 100

        # [INPUT GUARD]: target_type must be on the allow-list — otherwise an
        # arbitrary string reaches the dispatcher and dies without client feedback.
        target_type = params[:target_type].presence
        if target_type && !DEPLOY_TARGET_TYPES.include?(target_type)
          render json: {
            error: I18n.t("flash.firmwares.invalid_target_type", allowed: DEPLOY_TARGET_TYPES.join(", "))
          }, status: :bad_request
          return
        end

        # [HUMAN-ERROR GUARD]: деплой Tree-контракту з target_type=Gateway (чи
        # навпаки) — ознака плутанини оператора, не легітимний запит.
        if target_type && @firmware.target_hardware_type.present? && target_type != @firmware.target_hardware_type
          render json: {
            error: I18n.t("flash.firmwares.target_type_mismatch", expected: @firmware.target_hardware_type)
          }, status: :bad_request
          return
        end

        # [TENANT-ISOLATION]: cluster_id must belong to the caller's organization.
        # The dispatcher re-scopes through organization.clusters as well —
        # belt-and-suspenders on the cross-tenant OTA vector.
        cluster_id = params[:cluster_id].presence
        if cluster_id && !acting_organization!.clusters.exists?(id: cluster_id)
          render json: { error: I18n.t("errors.api.not_found", model: "Cluster") }, status: :not_found
          return
        end

        result = Ota::DeploymentDispatcherService.call(
          firmware: @firmware,
          organization: acting_organization!,
          cluster_id: cluster_id,
          canary_percentage: canary_percentage
        )

        if result.dispatched?
          respond_to do |format|
            format.json do
              render json: {
                message: I18n.t("flash.firmwares.deployment_dispatched", version: @firmware.version),
                target: cluster_id ? I18n.t("flash.firmwares.target_cluster", id: cluster_id) : I18n.t("flash.firmwares.target_all"),
                canary_percentage: canary_percentage,
                dispatched_gateways: result.dispatched_gateways,
                skipped_clusters: skipped_clusters_json(result)
              }, status: :accepted
            end
            format.html do
              redirect_to firmwares_path, pending: I18n.t("flash.firmwares.deployment_dispatched", version: @firmware.version)
            end
          end
        else
          # Нічого не затаргечено: oversized-гейт [FW.60] / anti-rollback / нема цілей.
          reason_key =
            if result.skipped_clusters.any? { |sc| sc.reason == "oversized_firmware" }
              "deployment_oversized"
            elsif result.skipped_clusters.any? { |sc| sc.reason == "rollback" }
              "deployment_rejected_stale"
            else
              "deployment_no_targets"
            end
          respond_to do |format|
            format.json do
              render json: {
                error: I18n.t("flash.firmwares.#{reason_key}"),
                skipped_clusters: skipped_clusters_json(result)
              }, status: :unprocessable_content
            end
            format.html do
              redirect_to firmwares_path, error: I18n.t("flash.firmwares.#{reason_key}")
            end
          end
        end
      end

      private

      # One-Home деривації інвентаря версій — його читають ДВА екшени: `index`
      # малює з нього панель, `#inventory` віддає ту саму пару машині (оголошена
      # API-поверхня, `04_03 §4.1`). Доти пара стояла дослівно двічі [UI.8].
      #
      # ⊥ Гілку «контексту немає» тримає ВИКЛИКАЧ, а не цей метод, і це не стиль:
      # `index` рендериться й без обраного клану, тож мусить розрізняти `nil` ⊥ `{}`
      # [ARCH.84], тоді як `#inventory` входить через `acting_organization!` —
      # організація там гарантована, і nil-гілка була б недосяжною.
      def firmware_inventory_for(organization)
        {
          trees: organization.trees.group(:firmware_version).count,
          gateways: organization.gateways.group(:firmware_version).count
        }
      end

      # 🔴 [SEC.25 Ф4] Доти — голий `render json:` у дії, чий успіх і чия валідаційна
      # відмова обидва мають `format.html`: оператор, що завантажив завеликий бінар
      # через справжню форму, діставав сирий блоб замість сторінки.
      #
      # Повідомлення кладеться в `errors` МОДЕЛІ, бо саме звідти його бере форма —
      # інакше вона повернулась би без жодного пояснення (та сама хвороба «канал без
      # споживача», яку цей пункт і лікує). JSON-половина віддає той самий текст у
      # незмінній формі `{ error: … }` — контракт API не зрушено.
      def render_oversized_upload
        message = I18n.t("flash.firmwares.file_too_large", limit: MAX_FIRMWARE_SIZE / 1.megabyte)

        respond_to do |format|
          format.json { render json: { error: message }, status: :unprocessable_content }
          format.html do
            @firmware.errors.add(:base, message)
            render_dashboard(
              title: I18n.t("firmwares.create_error_title"),
              component: Firmwares::New.new(firmware: @firmware),
              status: :unprocessable_content
            )
          end
        end
      end

      def skipped_clusters_json(result)
        result.skipped_clusters.map { |sc| { id: sc.id, name: sc.name, reason: sc.reason } }
      end

      def firmware_params
        # ⚠️ Кожен пермічений скаляр, крім `binary_file`/`bytecode_payload`, іде в
        # мас-присвоєння (`create` робить `.except` рівно на цю пару), тож ключ без
        # колонки — не «зайвий дозвіл», а `ActiveModel::UnknownAttributeError` → 500.
        # Саме так тут жили `target_hardware` і `notes`.
        params.require(:firmware).permit(:version, :binary_file, :target_hardware_type, :tree_family_id, :bytecode_payload)
      end
    end
  end
end
