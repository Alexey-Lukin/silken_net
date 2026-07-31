# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Api
  module V1
    class AuditLogsController < BaseController
      before_action :authorize_admin!

      # GET /api/v1/audit_logs
      # Журнал дій адміністраторів для запобігання фроду та помилкам
      def index
        @logs = readable_audit_logs
                  .includes(:user)
                  .recent

        # Фільтрація
        @logs = @logs.by_action(params[:action_type])
        @logs = @logs.by_user(params[:user_id])

        @pagy, @logs = pagy(@logs, limit: params.fetch(:limit, 50).to_i.clamp(1, 100))

        respond_to do |format|
          format.json do
            render json: {
              data: AuditLogBlueprint.render_as_hash(@logs, view: :index),
              pagy: pagy_metadata(@pagy)
            }
          end
          format.html do
            render_dashboard(
              title: I18n.t("audit_logs.index_title"),
              component: AuditLogs::Index.new(
              logs: @logs, pagy: @pagy,
              # Фільтри проводяться у в'ю ЯВНО: інакше пагінація губить їх на
              # другій сторінці, а відфільтрована видача невідрізнима від повної.
              filters: { user_id: params[:user_id].presence, action_type: params[:action_type].presence }
            )
            )
          end
        end
      end

      # GET /api/v1/audit_logs/:id
      def show
        @log = readable_audit_logs
                 .includes(:user)
                 .find(params[:id])

        respond_to do |format|
          format.json do
            render json: AuditLogBlueprint.render(@log, view: :show)
          end
          format.html do
            render_dashboard(
              title: I18n.t("audit_logs.show_title", id: @log.id),
              component: AuditLogs::Show.new(log: @log)
            )
          end
        end
      end

      private

      # [SEC.25 Ф2] Журнал acting-організації — ПЛЮС глобальний системний ланцюг для
      # super_admin.
      #
      # `organization_id: nil` в `audit_logs` не «запис без організації», а окремий
      # ланцюг: туди `Auditable` пише org-less дії, зокрема зміни `SystemParameter`
      # (governance-константи). Доти super_admin бачив саме його — не порожнечу й не
      # крос-тенант, — бо його власний `organization_id` теж `nil`, тож фільтр збігався
      # випадково. Під acting-org він дістав би id організації й **тихо втратив би
      # доступ до системного ланцюга**, і жоден тест не почервонів би: Pundit тут не
      # викликається взагалі (скоуп ручний), а власна політика була мертвим кодом і
      # знята ⚖️ 2026-07-31 разом із рештою дев'яти. ✅ Відтоді сторож існує —
      # `audit_logs_controller_spec` пінить видимість системного ланцюга під
      # super_admin (доти тут стояло «super_admin-спеки немає»: спеку написали, а
      # речення про її відсутність лишили).
      #
      # Org-admin глобального ланцюга не бачить — як і раніше.
      def readable_audit_logs
        org_ids = [ acting_organization!.id ]
        org_ids << nil if current_user.role_super_admin?

        AuditLog.where(organization_id: org_ids)
      end
    end
  end
end
