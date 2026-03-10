# frozen_string_literal: true

module Api
  module V1
    class OracleCallbacksController < BaseController
      # Chainlink DON callbacks are machine-to-machine — no user session.
      skip_before_action :authenticate_user!

      # POST /api/v1/oracle_callbacks
      def create
        request_id = params.require(:chainlink_request_id)
        log = TelemetryLog.find_by!(chainlink_request_id: request_id)

        if params[:success]
          log.update!(oracle_status: "fulfilled")

          # 🔗 CRITICAL: Trigger existing minting pipeline upon oracle fulfillment
          MintCarbonCoinWorker.perform_async(log.id)

          Rails.logger.info "✅ [Oracle Callback] TelemetryLog ##{log.id} fulfilled. Minting enqueued."

          render json: { status: "fulfilled", telemetry_log_id: log.id }, status: :ok
        else
          error_message = params[:error].presence || "Unknown oracle error"
          log.update!(oracle_status: "failed")

          Rails.logger.error "🚨 [Oracle Callback] TelemetryLog ##{log.id} failed: #{error_message}"

          render json: { status: "failed", telemetry_log_id: log.id, error: error_message }, status: :ok
        end
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Chainlink request not found" }, status: :not_found
      end
    end
  end
end
