# frozen_string_literal: true

module Api
  module V1
    class AuditLogsController < BaseController
      before_action :authorize_admin!

      # GET /api/v1/audit_logs
      # Журнал дій адміністраторів для запобігання фроду та помилкам
      def index
        @logs = AuditLog.where(organization_id: current_user.organization_id)
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
              title: "Audit Log",
              component: AuditLogs::Index.new(logs: @logs, pagy: @pagy)
            )
          end
        end
      end

      # GET /api/v1/audit_logs/:id
      def show
        @log = AuditLog.where(organization_id: current_user.organization_id)
                       .includes(:user)
                       .find(params[:id])

        respond_to do |format|
          format.json do
            render json: AuditLogBlueprint.render(@log, view: :show)
          end
          format.html do
            render_dashboard(
              title: "Audit Event ##{@log.id}",
              component: AuditLogs::Show.new(log: @log)
            )
          end
        end
      end
    end
  end
end
