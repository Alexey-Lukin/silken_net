# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Api
  module V1
    class MaintenanceRecordsController < BaseController
      include IdempotentRequest

      before_action :authorize_forester!
      before_action :set_record, only: [ :show, :edit, :update, :verify, :photos ]
      before_action :authorize_record_mutation!, only: [ :edit, :update, :verify ]

      # --- ЖУРНАЛ ВТРУЧАНЬ ---
      def index
        @records = organization_scoped_records
                     .includes(:user, :maintainable, photos_attachments: :blob)
                     .order(performed_at: :desc)

        if params[:maintainable_type].present? && params[:maintainable_id].present?
          @records = @records.where(
            maintainable_type: params[:maintainable_type],
            maintainable_id: params[:maintainable_id]
          )
        end

        @records = @records.where(action_type: params[:action_type]) if params[:action_type].present?
        @records = @records.hardware_verified if params[:verified].present?

        # [INPUT GUARD]: invalid ISO8601 dates passed to `where("performed_at >= ?")`
        # surface as `PG::InvalidDatetimeFormat` mid-query (HTTP 500). Parse and
        # validate once; if either bound is malformed, fail fast with 400 so the
        # client sees a clear error and Sentry doesn't see the noise.
        if params[:from].present?
          parsed_from = parse_iso8601_filter(params[:from])
          return render(json: { error: I18n.t("flash.maintenance.invalid_date", value: params[:from]) }, status: :bad_request) if parsed_from.nil?
          @records = @records.where("performed_at >= ?", parsed_from)
        end

        if params[:to].present?
          parsed_to = parse_iso8601_filter(params[:to])
          return render(json: { error: I18n.t("flash.maintenance.invalid_date", value: params[:to]) }, status: :bad_request) if parsed_to.nil?
          @records = @records.where("performed_at <= ?", parsed_to)
        end

        @pagy, @records = pagy(@records, limit: 50)

        respond_to do |format|
          format.json do
            render json: {
              data: MaintenanceRecordBlueprint.render_as_hash(@records, view: :index),
              pagy: { page: @pagy.page, limit: @pagy.limit, count: @pagy.count, pages: @pagy.last }
            }
          end
          format.html do
            render_dashboard(
              title: I18n.t("maintenance.index_title"),
              component: Maintenance::Index.new(records: @records, pagy: @pagy)
            )
          end
        end
      end

      # --- НОВА ФОРМА ---
      def new
        @record = current_user.maintenance_records.build(
          maintainable_type: params[:maintainable_type] || "Tree",
          maintainable_id: params[:maintainable_id],
          ews_alert_id: params[:ews_alert_id]
        )

        render_dashboard(
          title: I18n.t("maintenance.new_title"),
          component: Maintenance::Form.new(record: @record)
        )
      end

      # --- ФІКСАЦІЯ ЗЦІЛЕННЯ ---
      # [E.20 HARD-gate] `Idempotency-Key` — передумова offline-черги guild-клієнта:
      # без неї повтор запиту, чия відповідь загубилась у дорозі, створює ДРУГИЙ
      # запис про те саме втручання, а на записах обслуговування рахується
      # `critical_unmaintained?` у слешинг-тракті — тобто дубль тут не косметичний.
      # Форма взята з `actuators#execute` (єдиний наявний носій патерну), з ОДНІЄЮ
      # свідомою розбіжністю, яку не треба «уніфікувати»: там повтор віддає `202
      # Accepted`, бо наказ виконується асинхронно й на момент відповіді ще не
      # завершений; тут робота вже ЗАВЕРШЕНА, тож повтор віддає `200 OK` з тим
      # самим тілом. `201 Created` віддавати не можна — цим запитом не створено
      # нічого.
      def create
        # Скоуп — КОРИСТУВАЧ, а не запис: у момент перевірки запису ще не існує,
        # тож єдина стабільна координата це автор. Заразом це відсікає колізію
        # ключів між двома лісниками.
        return if handle_idempotency!(
          scope: "maintenance_record:#{current_user.id}",
          error: I18n.t("flash.maintenance.idempotency_required"),
          replay_status: :ok
        )

        @record = current_user.maintenance_records.build(maintenance_params)
        verify_maintainable_within_organization!(@record)

        if @record.save
          remember_idempotent_response!(
            message: I18n.t("flash.maintenance.record_created"),
            record: MaintenanceRecordBlueprint.render_as_hash(@record, view: :show)
          )

          respond_to do |format|
            format.json do
              render json: {
                message: I18n.t("flash.maintenance.record_created"),
                record: MaintenanceRecordBlueprint.render_as_hash(@record, view: :show)
              }, status: :created
            end
            format.html { redirect_to maintenance_record_path(@record), success: I18n.t("flash.maintenance.record_created") }
          end
        else
          respond_to do |format|
            format.json { render_validation_error(@record) }
            format.html do
              render_dashboard(
                title: I18n.t("maintenance.create_error_title"),
                component: Maintenance::Form.new(
                  record: @record,
                  # `@record` is freshly `.build`-ed above; a failed `save` never
                  # persists anything (AR validation/callback failure = no DB write),
                  # so it is never `persisted?` here — no photos can exist yet.
                  existing_photos: []
                ),
                # [SEC.25] Дзеркалить статус JSON-гілки: на `200` без редиректу Turbo
                # відповідь викидає, тож лісник у полі, чий запис не пройшов валідацію
                # (найчастіше — бракує обовʼязкового фото), не бачив НІЧОГО.
                status: :unprocessable_content
              )
            end
          end
        end
      end

      # --- ДЕТАЛІ ЗАПИСУ ---
      def show
        @pagy_photos, @photos = pagy(@record.photos, limit: 6)
        respond_to do |format|
          format.json { render json: MaintenanceRecordBlueprint.render_as_hash(@record, view: :show) }
          format.html do
            render_dashboard(
              title: I18n.t("maintenance.show_title", id: @record.id),
              # [UI.6] Актор проводиться явно: `show` бачить будь-який форестер org'и, а
              # `verify`/`edit`/видалення фото стоять за `authorize_record_mutation!`.
              component: Maintenance::Show.new(
                record: @record, photos: @photos, pagy_photos: @pagy_photos,
                current_user: current_user
              )
            )
          end
        end
      end

      # --- ФОРМА РЕДАГУВАННЯ ---
      # GET /maintenance_records/:id/edit
      def edit
        render_dashboard(
          title: I18n.t("maintenance.edit_title", id: @record.id),
          component: Maintenance::Form.new(
            record: @record,
            existing_photos: @record.photos.limit(6).to_a,
            # [UI.6] Актор — явно: галерея вирішує, чи показувати кнопку НЕЗВОРОТНОГО
            # видалення фотодоказу, і компонент більше не деривує це право з маршруту.
            current_user: current_user
          )
        )
      end

      # --- ПАГІНАЦІЯ ФОТО (Turbo Frame Load More) ---
      # GET /maintenance_records/:id/photos?page=N
      def photos
        @pagy_photos, @photos = pagy(@record.photos, limit: 6)
        # [UI.6] `editable:` проводиться сюди ТЕЖ, і це найпідступніший із сайтів: без
        # нього дефолт `false` мовчки знімав би кнопку видалення на сторінках 2+ у самого
        # АВТОРА — тобто fail-closed бив би не по чужому, а по тому, хто має право.
        render Maintenance::PhotosPage.new(
          record: @record, photos: @photos, pagy: @pagy_photos,
          editable: @record.mutable_by?(current_user)
        )
      end

      # --- РЕДАГУВАННЯ ЗАПИСУ ---
      def update
        if @record.update(maintenance_params)
          respond_to do |format|
            format.json do
              render json: {
                message: I18n.t("flash.maintenance.record_updated"),
                record: MaintenanceRecordBlueprint.render_as_hash(@record, view: :show)
              }
            end
            format.html { redirect_to maintenance_record_path(@record), status: :see_other, success: I18n.t("flash.maintenance.record_updated") }
          end
        else
          respond_to do |format|
            format.json { render_validation_error(@record) }
            format.html do
              render_dashboard(
                title: I18n.t("maintenance.edit_title", id: @record.id),
                component: Maintenance::Form.new(
                  record: @record,
                  existing_photos: @record.photos.limit(6).to_a,
                  current_user: current_user
                ),
                status: :unprocessable_content
              )
            end
          end
        end
      end

      # --- HARDWARE VERIFY (STM32 підтвердження) ---
      # [UI.7, ⚖️ 2026-08-20] Verify — це ЗВІРКА, не кнопка: прапорець ставиться
      # лише коли вузол справді вийшов в ефір ПІСЛЯ обслуговування
      # (`#hardware_pulse_confirmed?` — дім критерію на моделі). Доти update був
      # безумовний, тобто «залізне підтвердження» атестував той самий актор,
      # що вписує GPS руками, — другим кліком.
      # Guard-гілка контролера → `{ error: }` РЯДОК (не `errors:` масив —
      # контракт §25a: ключ відповіді сам називає гілку).
      def verify
        unless @record.hardware_pulse_confirmed?
          message = I18n.t("flash.maintenance.hardware_pulse_missing")
          respond_to do |format|
            format.json { render json: { error: message }, status: :unprocessable_content }
            format.html { redirect_to maintenance_record_path(@record), error: message }
          end
          return
        end

        if @record.update(hardware_verified: true)
          respond_to do |format|
            format.json do
              render json: {
                message: I18n.t("flash.maintenance.hardware_verified"),
                hardware_verified: true,
                record_id: @record.id
              }
            end
            format.html { redirect_to maintenance_record_path(@record), status: :see_other, success: I18n.t("flash.maintenance.hardware_verified") }
          end
        else
          # [SEC.25] Дзеркало форми успіху вище — доти невдала верифікація віддавала
          # патрульному JSON-блоб у браузер, тоді як успіх мав нормальний HTML-редирект.
          respond_to do |format|
            format.json { render_validation_error(@record) }
            format.html do
              redirect_to maintenance_record_path(@record),
                          error: @record.errors.full_messages.to_sentence
            end
          end
        end
      end

      private

      # Returns nil for malformed input, letting the caller produce a 400 instead
      # of leaking a server-side exception.
      #
      # `Time.zone.iso8601`, ніколи голий `Time.iso8601` [ARCH.92]: другий ігнорує
      # `config.time_zone` і читає зону ПРОЦЕСУ, тож `?from=2026-05-23T10:00:00`
      # (без суфікса) означав би різний момент на різних машинах — а це фільтр
      # НАД ЧУЖИМИ записами, тобто тихо віддавав би не ті рядки.
      #
      # ⚠️ Він же приймає дату-без-часу (`2026-05-23` → північ у зоні застосунку),
      # чого `Time.iso8601` не вміє — тобто фільтр за днем працює лише в цій формі.
      def parse_iso8601_filter(raw)
        Time.zone.iso8601(raw.to_s)
      rescue ArgumentError
        nil
      end

      # [AUTHZ FIX]: Forester could edit/verify another forester's maintenance
      # record within the same org — the only check was `authorize_forester!`.
      # Restrict mutations to the author; admin+ keep the override for audit.
      #
      # [UI.6] Саму формулу перенесено в `MaintenanceRecord#mutable_by?`: доти вона жила
      # приватним методом контролера, тож ані компонент (кнопки `verify`/`edit`), ані
      # вкладений photos-контролер дістати її не могли — і обидва через це її не мали.
      def authorize_record_mutation!
        return if @record.mutable_by?(current_user)

        # [SEC.25] Усі три гейтовані екшени (`edit`/`update`/`verify`) мають HTML-шлях.
        # ⚠️ Цей `respond_to` НЕ став зайвим після [UI.9] (де базовий `render_forbidden`
        # дістав власну HTML-гілку): там посадка — СТОРІНКА відмови, тут свідомо мʼяка,
        # назад у список. Різні дієслова, тож і різні місця; спільна лише JSON-половина.
        respond_to do |format|
          format.json { render_forbidden_json }
          format.html do
            redirect_to maintenance_records_path, status: :see_other, error: I18n.t("errors.api.forbidden")
          end
        end
      end

      def set_record
        @record = organization_scoped_records
                    .includes(photos_attachments: :blob)
                    .find(params[:id])
      end

      # Обмежуємо доступ до записів лише організацією поточного користувача
      def organization_scoped_records
        org_cluster_ids = acting_organization!.clusters.select(:id)

        MaintenanceRecord.where(
          "(maintainable_type = 'Tree' AND maintainable_id IN (?)) OR " \
          "(maintainable_type = 'Gateway' AND maintainable_id IN (?))",
          Tree.where(cluster_id: org_cluster_ids).select(:id),
          Gateway.where(cluster_id: org_cluster_ids).select(:id)
        )
      end

      # [SEC IDOR]: maintainable_id/ews_alert_id надходять клієнтом через
      # mass-assignment — без перевірки форестер org-A подавав би
      # decommissioning/biomass_extraction на дерево org-B (→ EcosystemHealingWorker
      # ретайрить/оголошує мертвим чуже дерево + каскад slashing) або гасив би
      # чужу ews-тривогу. Дзеркало organization_scoped_records, застосоване ДО save.
      def verify_maintainable_within_organization!(record)
        target = record.maintainable
        # Відсутній/неіснуючий maintainable — НЕ security-кейс: хай модельна
        # валідація (`belongs_to :maintainable` required) поверне 422, не 404.
        # Гард ловить лише ІСНУЮЧИЙ-але-чужий maintainable (cross-tenant IDOR).
        return if target.nil?

        owned =
          case target
          when Tree, Gateway
            acting_organization!.clusters.exists?(id: target.cluster_id)
          else
            false
          end
        raise ActiveRecord::RecordNotFound unless owned

        if record.ews_alert_id.present? &&
           !acting_organization!.ews_alerts.exists?(id: record.ews_alert_id)
          raise ActiveRecord::RecordNotFound
        end
      end

      def maintenance_params
        params.require(:maintenance_record).permit(
          :maintainable_id, :maintainable_type, :ews_alert_id,
          :action_type, :notes, :performed_at,
          :labor_hours, :parts_cost,
          :hardware_verified,
          :latitude, :longitude,
          photos: []
        )
      end
    end
  end
end
