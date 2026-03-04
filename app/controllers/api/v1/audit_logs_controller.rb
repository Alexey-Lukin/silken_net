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
        @logs = @logs.limit(params.fetch(:limit, 50).to_i.clamp(1, 100))

        render json: @logs.as_json(
          only: [ :id, :action, :auditable_type, :auditable_id, :metadata, :created_at ],
          include: { user: { only: [ :id, :email_address, :first_name, :last_name, :role ] } }
        )
      end

      # GET /api/v1/audit_logs/:id
      def show
        @log = AuditLog.where(organization_id: current_user.organization_id).find(params[:id])

        render json: @log.as_json(
          only: [ :id, :action, :auditable_type, :auditable_id, :metadata, :created_at ],
          include: { user: { only: [ :id, :email_address, :first_name, :last_name, :role ] } }
        )
      end
    end
  end
end
