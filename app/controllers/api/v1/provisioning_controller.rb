# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Api
  module V1
    class ProvisioningController < BaseController
      before_action :authorize_forester!

      # --- ТЕРМІНАЛ ІНІЦІАЦІЇ ---
      def new
        @clusters = acting_organization!.clusters
        # [ВИПРАВЛЕНО: Unbounded Query]: Використовуємо alphabetical скоуп замість .all.
        # TreeFamily — довідник видів (~100-1000 записів), але .all не має ORDER BY
        # та не обмежує вибірку. alphabetical забезпечує детермінований порядок.
        @families = TreeFamily.alphabetical

        render_dashboard(
          title: I18n.t("provisioning.new_title"),
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
            # [SEC.25 Ф4] Форма провізії — браузерна, тож голий `render json:` тут
            # означав сирий блоб замість форми з поясненням. Гілку досяжно одним
            # кліком: поле `hardware_uid` вільне, а лісник вводить UID з кремнію.
            respond_to do |format|
              format.json do
                render json: { error: I18n.t("flash.provisioning.invalid_uid", uid: normalized_uid) },
                       status: :unprocessable_content
              end
              format.html do
                render_new_with_errors(message: I18n.t("flash.provisioning.invalid_uid", uid: normalized_uid))
              end
            end
            return
          end
        end

        # [ЗАХИСТ ВІД ПОДВІЙНОЇ ІНІЦІАЦІЇ]: перевіряємо той ідентифікатор, під
        # яким provision реально пише HardwareKey (Tree → derived DID; Gateway
        # → uid). До FW.54 тут стояв сирий hardware_uid — для дерев guard був
        # мертвий (provision зберігає "SNET-…", не 24-hex вхід).
        guard_identifier = tree_did || normalized_uid
        if HardwareKey.exists?(device_uid: guard_identifier)
          # [SEC.25 Ф4] Найбуденніший шлях сюди — повторна відправка тієї самої
          # форми (подвійний клік / «назад» після успіху), тобто саме браузер.
          respond_to do |format|
            format.json do
              render json: { error: I18n.t("flash.provisioning.uid_taken", uid: guard_identifier) }, status: :conflict
            end
            format.html do
              render_new_with_errors(
                message: I18n.t("flash.provisioning.uid_taken", uid: guard_identifier),
                status: :conflict
              )
            end
          end
          return
        end

        # [SEC IDOR]: cluster_id надходить від клієнта — переконуємось, що він
        # належить організації форестера (дзеркало firmwares#deploy, який цей клас
        # багу вже закрив; сиблінг oracle_visions#simulate знято 2026-08-15 разом
        # із мертвою фічею — [UI.7]). Без цього
        # форестер org-A провізіонить пристрій + HardwareKey + DID у кластер org-B.
        unless acting_organization!.clusters.exists?(id: provisioning_params[:cluster_id])
          # [SEC.25 Ф4] Досяжно БЕЗ підміни значення: `<select>` пропонує лише свої
          # кластери, але організація запиту резолвиться щоразу наново, тож
          # super_admin, який перемкнув контекст у сусідній вкладці й відправив уже
          # відкриту форму, потрапляє сюди легітимно. Тому — форма з поясненням, а
          # не сторінка «не знайдено»: помилку видно там, де її можна виправити.
          respond_to do |format|
            format.json do
              render json: { error: I18n.t("errors.api.not_found", model: "Cluster") }, status: :not_found
            end
            format.html do
              render_new_with_errors(
                message: I18n.t("errors.api.not_found", model: "Cluster"),
                status: :not_found
              )
            end
          end
          return
        end

        # [ARCH.59] Транзакція охоплює РІВНО те, що мусить бути атомарним:
        # пристрій + ключі + запис монтажу. Enqueue і відповідь — після коміту
        # (нижче), бо доти вони стояли всередині: Sidekiq бачив джобу до коміту
        # (phantom-job), а HTTP-рендер тримав PG-транзакцію відкритою на весь
        # час серіалізації. Правильна форма стояла поруч увесь час —
        # `MaintenanceRecord` вішає свій пост-ефект на `after_create_commit`.
        device_identifier = nil

        ActiveRecord::Base.transaction do
          @device = build_device(provisioning_params)

          if @device.is_a?(Tree)
            @device.did             = tree_did
            @device.silicon_uid_hex = normalized_uid
            device_identifier = @device.did
          else
            device_identifier = @device.uid
          end

          next unless @device.save

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
            system_generated: true
          )
        end

        unless @device.persisted?
          return respond_to do |format|
            format.json { render_validation_error(@device) }
            format.html { render_new_with_errors }
          end
        end

        # РЕЄСТРАЦІЯ PEAQ DID (Machine Identity) — ПІСЛЯ коміту [ARCH.59].
        # [ARCH.119] Activation-gated: несконфігурована нога дала б 6 гарантовано
        # провальних виконань на кожне дерево. Пропуск нічого не губить — `peaq_did IS NULL`
        # і є маркером, а `PeaqBackfillWorker` дренажить його після активації.
        if @device.is_a?(Tree) && Peaq::DidRegistryService.configured?
          PeaqRegistrationWorker.perform_async(@device.id)
        end

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
          # [SEC.25] 🔴 Тут був НАЙДОРОЖЧИЙ екземпляр класу: успіх провізії
          # рендерився як `200` без редиректу, а Turbo такі відповіді на сабміт
          # викидає мовчки. Тобто лісник тиснув «Provision», пристрій
          # створювався, `HardwareKey` писався, `PeaqRegistrationWorker` летів —
          # і сторінка не ворушилась. Найгірша форма німоти в дереві: не «дія не
          # вдалась», а «дія вдалась, і про це не сказано».
          #
          # Лік — PRG на сторінку самого пристрою, а не окрема сторінка успіху:
          # `trees/show` уже показує `did` заголовком і `device_uid` у
          # hardware-vault, `gateways/show` — `uid` у шапці. Тобто все, що
          # виводила знята сторінка успіху, там уже є, і в контексті.
          # `flash.provisioning.node_initiated` уже написаний у 4 локалях і тепер
          # має де відрендеритись.
          format.html do
            redirect_to device_path_after_provisioning(@device),
                        status: :see_other,
                        success: I18n.t("flash.provisioning.node_initiated",
                                       did: device_identifier,
                                       uid: provisioning_params[:hardware_uid])
          end
        end
      rescue StandardError => e
        # [SEC.25 Ф4] Доти цей локальний перехоплювач стояв ПЕРЕД класовим
        # `rescue_from` і віддавав голий JSON — тобто локально відтворював рівно
        # той дефект, який глобально вже закрито (сира JSON у браузері).
        # Рендер делегується — дублювати `respond_to` немає навіщо, у базового він
        # повний. ⚠️ Доменний лог лишається СВІДОМО, хоч делегат теж логує (той
        # пише `fatal` без доменного префікса): аварія провізії лягає в лог двічі,
        # і це прийнята ціна за те, щоб її можна було грепнути за `[Provisioning]`.
        Rails.logger.error "🚨 [Provisioning] Збій ініціації: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
        render_internal_server_error(e)
      end

      private

      # Дерево і Королева мають різні сторінки; обидві вже показують ідентифікатор,
      # який лісник звіряє з кремнієм.
      def device_path_after_provisioning(device)
        device.is_a?(Tree) ? tree_path(device) : gateway_path(device)
      end

      # `message:` — для ранніх гілок (`invalid_uid` · `uid_taken` · чужий кластер),
      # де @device ще не збудовано: помилка мусить приїхати в те саме місце, що й
      # модельна валідація, інакше вона для лісника виглядає інакшим класом події.
      # `status:` параметризовано, бо ці гілки не 422 (409 / 404).
      def render_new_with_errors(message: nil, status: :unprocessable_content)
        @clusters = acting_organization!.clusters
        @families = TreeFamily.alphabetical
        @device ||= Tree.new
        @device.errors.add(:base, message) if message

        render_dashboard(
          title: I18n.t("provisioning.failed_title"),
          component: Provisioning::New.new(
            clusters: @clusters,
            families: @families,
            device: @device
          ),
          # [SEC.25] Без цього Turbo викидав відповідь, і форма з помилками
          # валідації виглядала для лісника як мертва кнопка «Provision».
          status: status
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
