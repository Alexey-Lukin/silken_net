# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Api
  module V1
    class SystemAuditsController < BaseController
      # [SEC]: ChainAuditService рахує ПЛАТФОРМО-ГЛОБАЛЬНИЙ db↔chain reconcile
      # (+critical fraud-flag) — не org-scoped. Лише admin+ (дзеркало
      # SystemHealthController), інакше будь-який subscriber будь-якої org бачить
      # у реальному часі сигнал десинхронізації/можливого фроду всієї платформи.
      before_action :authorize_admin!

      # GET /system_audits
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
              title: I18n.t("system_audits.index_title"),
              component: SystemAudits::Index.new(audit: @audit)
            )
          end
        end
      end
    end
  end
end
