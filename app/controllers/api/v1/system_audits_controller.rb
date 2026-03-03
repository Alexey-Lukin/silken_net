# frozen_string_literal: true

module Api
  module V1
    class SystemAuditsController < BaseController
      # GET /api/v1/system_audits
      def index
        @audit = ChainAuditService.call

        respond_to do |format|
          format.json do
            render json: {
              db_total:    @audit.db_total,
              chain_total: @audit.chain_total,
              delta:       @audit.delta,
              critical:    @audit.critical,
              checked_at:  @audit.checked_at
            }
          end
          format.html do
            render_dashboard(
              title: "System Audit",
              component: Views::Components::SystemAudits::Index.new(audit: @audit)
            )
          end
        end
      end
    end
  end
end
