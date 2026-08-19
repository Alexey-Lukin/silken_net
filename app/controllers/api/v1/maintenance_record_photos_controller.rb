# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Api
  module V1
    # Видалення окремого фото з MaintenanceRecord.
    # DELETE /maintenance_records/:maintenance_record_id/photos/:id
    class MaintenanceRecordPhotosController < BaseController
      before_action :authorize_forester!
      before_action :set_record
      # [UI.6] Дзеркало гарда батьківського контролера, якого тут бракувало. Коміт, що
      # закрив «Forester #2 within the same org» на `edit`/`update`/`verify`, цього шляху
      # не торкнувся — а він мутує ТОЙ САМИЙ запис, тож будь-який форестер організації
      # видаляв фотодокази з чужого. Наслідок важчий за батьківський: там посадка мʼяка
      # (403), тут дія ПРОХОДИЛА — незворотно (`purge_later` → S3) і безслідно
      # (`MaintenanceRecord` поза `Auditable`-периметром, [SEC.28]).
      # Стоїть ПІСЛЯ `set_record`, бо читає `@record`; без `only:` — екшен тут один.
      before_action :authorize_record_mutation!
      before_action :set_photo
      # [SEC.28] Стоїть ПІСЛЯ `set_photo` і ПЕРЕД `destroy`: відмова мусить статися до
      # того, як щось незворотне почалось.
      before_action :guard_evidence_purge!

      def destroy
        # 🔴 [SEC.28] Слід ПЕРЕД знищенням, і він мусить нести ІДЕНТИЧНІСТЬ блоба,
        # а не сам факт. Підстава конкретна: доказ після `purge_later` не
        # відновити, тож запис «фото видалено» дав би нуль для розслідування —
        # чим саме він був, встановити вже нічим. Імʼя, розмір і checksum
        # лишаються єдиною ниткою, якою знищений блоб можна звірити із зовнішньою
        # копією (польовий телефон, експорт, лист).
        record_audit_trail_for_purge!
        @photo.purge_later # async — не блокуємо запит, S3 deletion в Sidekiq
        respond_to do |format|
          format.json { render json: { message: I18n.t("flash.maintenance.photo_deleted") }, status: :ok }
          # 303, не 302 [UI.7]: `fetch` конвертує 301/302 у GET лише для POST, а
          # DELETE зберігає — тож браузер перевидавав би DELETE на сторінку запису,
          # де зареєстровано лише GET. Найгірша форма симптому саме тут: фото вже
          # знищене НЕЗВОРОТНО (`purge_later` → S3), а користувач бачить помилку.
          format.html do
            redirect_to maintenance_record_path(@record),
                        status: :see_other,
                        success: I18n.t("flash.maintenance.photo_deleted")
          end
        end
      end

      private

      # [SEC.28] ⚖️ Присуд founder: доказ не має СТРОКУ зберігання — він має ГАРД
      # (форма з ратифікованої доктрини гаманця, `Wallet#guard_mrv_evidence!`). Умова
      # живе на моделі — `MaintenanceRecord#evidence_backed?` — бо її читають ТРИ місця;
      # тут лише посадка.
      #
      # 🔴 Підстава подвійна, і обидві половини виміряні. (1) `purge_later` запис НЕ
      # зберігає, тож зняте ОСТАННЄ фото лишало `repair`/`installation` назавжди
      # невалідним: `photos_required_for_critical_actions` оголошено без `on:`, тобто
      # біжить на кожному наступному `save`, і полагодити запис уже нічим.
      # (2) `BlockchainBurningService#critical_unmaintained?` тим часом бачив ТОЙ САМИЙ
      # запис і далі гасив `PF_NO_MAINTENANCE` — тобто економічний ефект «обслуговування
      # відбулося» переживав знищення власного доказу. Виправлення робиться ДОДАВАННЯМ
      # кадру, не зняттям — як і на кожній іншій доказовій поверхні платформи.
      def guard_evidence_purge!
        return unless @record.evidence_backed?

        message = I18n.t("flash.maintenance.photo_evidence_locked")
        respond_to do |format|
          format.json { render json: { error: message }, status: :unprocessable_content }
          format.html do
            redirect_to maintenance_record_path(@record), status: :see_other, error: message
          end
        end
      end

      # Формула — не тут: дім = `MaintenanceRecord#mutable_by?`, той самий предикат, що
      # читає батьківський гард і що фільтрує кнопку в `PhotoCard`.
      #
      # ⚠️ Посадка ведеться на сторінку ЗАПИСУ, а не на index (як у батька): кнопка «×»
      # живе саме на `show`, тож викидати з неї глядача не було б за що. Після [UI.9]
      # базовий `render_forbidden` уже вміє HTML, але веде на СТОРІНКУ відмови —
      # інше дієслово, тож локальний `respond_to` лишається; спільна лише JSON-половина.
      #
      # ⚠️ Тут доти стояла «чесна межа: `alert:` тут НЕ бачить ніхто» — знято
      # [SEC.25]: `DashboardLayout` тепер рендерить `flash`, тож посадка більше не
      # мовчазна. Досяжність гілки лишається малою: не-автор кнопки вже не бачить,
      # тож сюди приходять лише зкрафтлений запит або гонка «сторінка відрендерена
      # → право відкликано».
      # [SEC.28] Викликається ДО `purge_later`: після нього `@photo.blob` уже
      # може бути в дорозі до знищення, і метадані нема з чого зібрати.
      # ⚠️ Організація береться з `acting_organization` (SEC.25 Ф2), не з
      # `current_user.organization`: super_admin працює в контексті однієї
      # організації за раз, і слід мусить нести саме контекст дії.
      # 🔴 `AuditLog.create!`, а НЕ штатний `record_audit_trail!` — і підстава та
      # сама, що вже задокументована в `organizations_controller#record_switch!`,
      # лише сильніша. Хелпер іде через `record_async!` → `AuditLogWorker`, тобто
      # ставить джобу в чергу: «слід перед знищенням» там означало б порядок
      # ВИКЛИКУ, а не порядок ПЕРСИСТЕНЦІЇ. При зупиненому Sidekiq фото зникло б
      # незворотно, а сліду не лишилось би взагалі — тобто асинхронний запис
      # відтворює РІВНО ту пару властивостей, проти якої SEC.28 і стоїть.
      # `create!` пише рядок синхронно, і `before_create :compute_chain_hash`
      # вбудовує його в tamper-evident ланцюг тут-таки.
      #
      # ⚠️ Викликається ДО `purge_later`: після нього блоб уже в дорозі до
      # знищення, і метадані нема з чого зібрати.
      # ⚠️ Організація — з `acting_organization` (SEC.25 Ф2), не з
      # `current_user.organization`: super_admin працює в контексті однієї
      # організації за раз, і ланцюг будується per-org.
      # ⚠️ Без `&.` СВІДОМО, обидва рази — safe-navigation тут створила б
      # непокривані nil-плечі на гілках, недосяжних за побудовою (той самий клас,
      # що вже коштував гілкового покриття раніше). `ActiveStorage::Attachment`
      # має `belongs_to :blob` обовʼязковим, тож блоба без блоба не буває; а
      # `acting_organization!` — оголошений контракт (SEC.25 Ф2), і його виняток
      # чесніший за тихий `nil` у полі, за яким будується per-org ланцюг.
      def record_audit_trail_for_purge!
        blob = @photo.blob

        AuditLog.create!(
          user_id: current_user.id,
          organization_id: acting_organization!.id,
          action: "maintenance_photo_purged",
          auditable_type: @record.class.name,
          auditable_id: @record.id,
          ip_address: request.remote_ip,
          user_agent: request.user_agent,
          metadata: {
            attachment_id: @photo.id,
            filename: blob.filename.to_s,
            byte_size: blob.byte_size,
            checksum: blob.checksum,
            content_type: blob.content_type
          }
        )
      end

      def authorize_record_mutation!
        return if @record.mutable_by?(current_user)

        respond_to do |format|
          format.json { render_forbidden_json }
          format.html do
            redirect_to maintenance_record_path(@record), status: :see_other, error: I18n.t("errors.api.forbidden")
          end
        end
      end

      def set_record
        org_cluster_ids = acting_organization!.clusters.select(:id)

        @record = MaintenanceRecord.where(
          "(maintainable_type = 'Tree' AND maintainable_id IN (?)) OR " \
          "(maintainable_type = 'Gateway' AND maintainable_id IN (?))",
          Tree.where(cluster_id: org_cluster_ids).select(:id),
          Gateway.where(cluster_id: org_cluster_ids).select(:id)
        ).find(params[:maintenance_record_id])
      end

      # [SEC.25 Ф4] Досяжно подвійним кліком по «×»: `purge_later` асинхронний, тож
      # другий клік (або друга відкрита вкладка) приходить на вже знятий доказ.
      # Посадка та сама, що в сусіднього гарда цього ж контролера — сторінка
      # запису, де живе кнопка.
      def set_photo
        @photo = @record.photos.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        respond_to do |format|
          format.json { render json: { error: I18n.t("flash.maintenance.photo_not_found") }, status: :not_found }
          format.html do
            redirect_to maintenance_record_path(@record),
                        status: :see_other,
                        error: I18n.t("flash.maintenance.photo_not_found")
          end
        end
      end
    end
  end
end
