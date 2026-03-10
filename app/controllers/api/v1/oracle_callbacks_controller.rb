# frozen_string_literal: true

module Api
  module V1
    class OracleCallbacksController < BaseController
      # Chainlink DON callbacks are machine-to-machine — no user session.
      skip_before_action :authenticate_user!

      # POST /api/v1/oracle_callbacks
      def create
        request_id = params.require(:chainlink_request_id)
        log = find_telemetry_log(request_id)

        if ActiveModel::Type::Boolean.new.cast(params[:success])
          log.update!(oracle_status: "fulfilled")

          # 🔗 CRITICAL: Trigger existing minting pipeline upon oracle fulfillment.
          # [COMPOSITE PK]: telemetry_logs uses [id, created_at] composite key
          # due to partitioning. Use id_value to extract the integer ID for Sidekiq.
          MintCarbonCoinWorker.perform_async(log.id_value)

          Rails.logger.info "✅ [Oracle Callback] TelemetryLog ##{log.id_value} fulfilled. Minting enqueued."

          render json: { status: "fulfilled", telemetry_log_id: log.id_value }, status: :ok
        else
          error_message = params[:error].presence || "Unknown oracle error"
          log.update!(oracle_status: "failed")

          Rails.logger.error "🚨 [Oracle Callback] TelemetryLog ##{log.id_value} failed: #{error_message}"

          render json: { status: "failed", telemetry_log_id: log.id_value, error: error_message }, status: :ok
        end
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Chainlink request not found" }, status: :not_found
      end

      private

      # [SCALE]: telemetry_logs is PARTITION BY RANGE (created_at).
      # When created_at is provided in the callback, PostgreSQL prunes to a single
      # partition instead of scanning chainlink_request_id indexes across all partitions.
      # At billions of rows this is the difference between O(log N) and O(P × log N).
      def find_telemetry_log(request_id)
        scope = TelemetryLog.where(chainlink_request_id: request_id)

        if params[:created_at].present?
          begin
            parsed_time = Time.iso8601(params[:created_at])
            scope = scope.where(created_at: parsed_time)
          rescue ArgumentError => e
            Rails.logger.warn "⚠️ [Oracle Callback] Malformed created_at ignored: #{e.message}"
          end
        end

        scope.first!
      end
    end
  end
end
