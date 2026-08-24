# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Api
  module V1
    class AlertsController < BaseController
      before_action :set_alert, only: [ :show, :resolve, :claim, :release ]
      # [SEC]: resolve = операційна дія (закрити бойову тривогу пожежі/tamper) —
      # лише forester+. Намір колись декларувала `EwsAlertPolicy#resolve?`, якої
      # контролер ніколи не викликав, тож investor (read-only роль) міг гасити активну
      # EWS-тривогу. Політику знято як мертвий код ⚖️ 2026-07-31, і цей гард лишився
      # ЄДИНИМ носієм правила — не прибирай його «бо десь є політика».
      # 🔴 Перелік ПОІМЕННИЙ, тож кожна нова операційна дія мусить дописатись сюди
      # руками — інакше вона їде без гарда, і мовчки: investor (read-only роль)
      # дістав би право диспетчеризувати бойові тривоги. Дії, не читання.
      before_action :authorize_forester!, only: [ :resolve, :claim, :release ]

      # GET /alerts
      def index
        @alerts = acting_organization!.ews_alerts
                              .includes(:cluster, :tree)
                              .order(created_at: :desc)

        # Фільтрація — параметри клієнта обмежуємо до enum-словника моделі,
        # інакше довільна строка ламає AR PG::InvalidTextRepresentation
        # та поглинає Sentry events. .keys повертає коректний whitelist.
        status_param = params[:status].presence&.to_s || "active"
        if EwsAlert.statuses.key?(status_param)
          @alerts = @alerts.where(status: status_param)
        else
          render json: { error: I18n.t("flash.alerts.invalid_status", value: status_param) }, status: :bad_request
          return
        end

        if params[:severity].present?
          severity_param = params[:severity].to_s
          unless EwsAlert.severities.key?(severity_param)
            render json: { error: I18n.t("flash.alerts.invalid_severity", value: severity_param) }, status: :bad_request
            return
          end
          @alerts = @alerts.where(severity: severity_param)
        end

        @alerts = @alerts.where(cluster_id: params[:cluster_id]) if params[:cluster_id].present?

        @pagy, @alerts = pagy(@alerts)

        respond_to do |format|
          format.json do
            render json: {
              data: @alerts.as_json(
                include: {
                  cluster: { only: [ :id, :name ] },
                  tree: { only: [ :id, :did, :latitude, :longitude ] }
                },
                methods: [ :coordinates, :actionable? ]
              ),
              pagy: pagy_metadata(@pagy)
            }
          end
          format.html do
            render_dashboard(
              title: I18n.t("alerts.index_title"),
              component: Alerts::Index.new(alerts: @alerts, pagy: @pagy, organization: acting_organization!,
                                           current_user: current_user)
            )
          end
        end
      end

      # GET /alerts/:id
      def show
        respond_to do |format|
          format.json do
            render json: {
              data: @alert.as_json(
                include: {
                  cluster: { only: [ :id, :name ] },
                  tree: { only: [ :id, :did, :latitude, :longitude ] }
                },
                methods: [ :coordinates, :actionable? ]
              )
            }
          end
          format.html do
            # [ARCH.31] Show = рядок у ВАЛІДНІЙ table-обгортці + SOP-панель
            # (доти рендерився голий <tr> поза table — браузер викидав його з DOM).
            render_dashboard(
              title: I18n.t("alerts.show_title", id: @alert.id),
              component: Alerts::Show.new(alert: @alert, current_user: current_user)
            )
          end
        end
      end

      # PATCH /alerts/:id/resolve
      # 🔴 [SEC.25] `if @alert.resolve!` тут БУЛО оманою, і фікс 2026-07-30 спершу полатав
      # саме її: `EwsAlert#resolve!` завершується літеральним `true`, а `mark_resolved!`
      # (AASM bang) і `whiny_persistence: true` не повертають `false` — вони КИДАЮТЬ.
      # Тобто `else`-гілка була недосяжна, а живий шлях відмови — повторний клік, який
      # описує коментар нижче, — летів у `rescue_from StandardError` і давав операторові
      # JSON-500 у браузері. Тепер відмова обробляється там, де вона реально виникає.
      def resolve
        @alert.resolve!(user: current_user, notes: params[:notes])

        respond_to do |format|
            format.json { render json: { message: I18n.t("flash.alerts.acknowledged", id: @alert.id), alert: @alert } }
            format.turbo_stream do
              # `dom_id`, а НЕ рукописний `alert_#{id}`: рядок рендериться як
              # `ews_alert_{id}`, тож стара ціль не існувала в жодній сторінці
              # застосунку і replace був тихим no-op. UX тримався виключно на
              # асинхронному броадкасті, у якого 5-секундний тротл — тобто при
              # збігу оператор не бачив нічого й тиснув «Вирішити» вдруге,
              # дістаючи вже відмову AASM.
              render turbo_stream: turbo_stream.replace(
                ActionView::RecordIdentifier.dom_id(@alert),
                # [ARCH.31] Адресу будує ПРОДЮСЕР, і тут це не стиль: у `.call`
                # немає view-контексту, тож `alert_path` усередині компонента дав би
                # `default_url_options for nil` — 500 на дії оператора. Stream
                # замінює рядок у РЕЄСТРІ, тож вхід на SOP-сторінку мусить пережити
                # підтвердження тривоги — саме там, де оператор щойно діяв.
                Alerts::Row.new(alert: @alert, current_user: current_user,
                                detail_href: alert_path(@alert)).call
              )
            end
          format.html { redirect_to alerts_path, success: I18n.t("flash.alerts.resolved") }
        end
      rescue AASM::InvalidTransition
        # Тривогу вже закрито — типово другим кліком по кнопці, поки перший ще летів
        # (див. тротл броадкасту вище). Це НЕ помилка сервера: 409 замість 500, і
        # формати ті самі, що в успіху.
        respond_to do |format|
          format.json do
            render json: { error: I18n.t("flash.alerts.already_resolved", id: @alert.id) }, status: :conflict
          end
          format.html do
            redirect_to alerts_path, pending: I18n.t("flash.alerts.already_resolved", id: @alert.id)
          end
        end
      end

      # PATCH /alerts/:id/claim
      # [E.20] Форма й обробка відмови дзеркалять `#resolve`: модель кидає,
      # контролер перекладає в код. 409 саме тому, що це КОНФЛІКТ стану, а не
      # невалідний запит — тривогу вже взяв інший лісник.
      def claim
        @alert.claim!(current_user)
        render_assignment_result(:claimed)
      rescue EwsAlert::AlreadyAssigned
        render_assignment_conflict(:already_assigned)
      rescue EwsAlert::AlertClosed
        render_assignment_conflict(:already_resolved)
      end

      # PATCH /alerts/:id/release
      def release
        @alert.release!(current_user)
        render_assignment_result(:released)
      rescue EwsAlert::NotAssignee
        # 403, а не 409: стан коректний, бракує ПРАВА — відпустити чуже може лише
        # admin+ (інакше один хибний клік замикав би тривогу на людині назавжди).
        respond_to do |format|
          format.json { render json: { error: I18n.t("flash.alerts.not_assignee") }, status: :forbidden }
          format.html { redirect_to alert_path(@alert), error: I18n.t("flash.alerts.not_assignee") }
        end
      end

      private

      def render_assignment_result(kind)
        respond_to do |format|
          format.json { render json: { message: I18n.t("flash.alerts.#{kind}", id: @alert.id), alert: @alert } }
          format.html { redirect_to alert_path(@alert), success: I18n.t("flash.alerts.#{kind}", id: @alert.id) }
        end
      end

      def render_assignment_conflict(key)
        message = I18n.t("flash.alerts.#{key}", id: @alert.id)

        respond_to do |format|
          format.json { render json: { error: message }, status: :conflict }
          format.html { redirect_to alert_path(@alert), pending: message }
        end
      end

      def set_alert
        @alert = acting_organization!.ews_alerts.find(params[:id])
      end
    end
  end
end
