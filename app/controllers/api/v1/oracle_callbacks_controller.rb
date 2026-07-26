# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Api
  module V1
    class OracleCallbacksController < BaseController
      # Chainlink DON callbacks are machine-to-machine — no user session.
      skip_before_action :authenticate_user!

      # [P1 WARNING FIX]: HMAC-SHA256 валідація підпису Chainlink DON.
      before_action :verify_chainlink_signature!

      # POST /api/v1/oracle_callbacks
      #
      # [A-6 FIX]: State Machine Guard — Replay Attack Prevention.
      # Atomic update_all with WHERE oracle_status='dispatched' ensures that only
      # the FIRST callback for a given telemetry log is processed. Subsequent
      # replays (identical HMAC-signed requests) hit zero rows and receive 409 Conflict.
      # This eliminates the need for timestamp/nonce in the HMAC payload.
      def create
        request_id = params.require(:chainlink_request_id)
        log = find_telemetry_log(request_id)

        new_status = ActiveModel::Type::Boolean.new.cast(params[:success]) ? "fulfilled" : "failed"

        # Atomic state transition: dispatched → fulfilled/failed.
        # Returns 0 if already processed (replay) or in unexpected state.
        updated_rows = TelemetryLog.where(id: log.id, created_at: log.created_at, oracle_status: "dispatched")
                                   .update_all(oracle_status: new_status)

        if updated_rows.zero?
          Rails.logger.warn "⚠️ [Oracle Replay] Blocked duplicate callback for TelemetryLog ##{log.id_value} " \
                            "(current status: #{log.oracle_status})"
          return head :conflict
        end

        if new_status == "fulfilled"
          # 🔗 CRITICAL: Trigger DUAL minting pipeline upon oracle fulfillment.
          # [COMPOSITE PK]: telemetry_logs uses [id, created_at] composite key
          # due to partitioning. Pass both id_value and created_at for partition pruning.
          created_at_iso = log.created_at.iso8601(6)

          # 1. EVM (Polygon) — мінтинг SCC/SFC для інституційних інвесторів (RWA)
          MintCarbonCoinWorker.perform_async(log.id_value, created_at_iso)

          # 2. Solana — миттєва мікро-винагорода для власника дерева (швидкість + 0 комісій)
          SolanaMicroRewardWorker.perform_async(log.id_value, created_at_iso)

          Rails.logger.info "✅ [Oracle Callback] TelemetryLog ##{log.id_value} fulfilled. EVM + Solana minting enqueued."

          render json: { status: "fulfilled", telemetry_log_id: log.id_value }, status: :ok
        else
          error_message = params[:error].presence || "Unknown oracle error"

          Rails.logger.error "🚨 [Oracle Callback] TelemetryLog ##{log.id_value} failed: #{error_message}"

          render json: { status: "failed", telemetry_log_id: log.id_value, error: error_message }, status: :ok
        end
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Chainlink request not found" }, status: :not_found
      end

      private

      # [P1 WARNING FIX]: Верифікація HMAC-SHA256 підпису Chainlink DON.
      # Заголовок X-Chainlink-Signature містить HMAC-SHA256(request_body, shared_secret).
      # Якщо CHAINLINK_HMAC_SECRET не встановлено (dev/test), пропускаємо перевірку з попередженням.
      def verify_chainlink_signature!
        hmac_secret = ENV["CHAINLINK_HMAC_SECRET"]

        if hmac_secret.blank?
          # [SEC.5 FIX]: Fail-closed у production. Коментар раніше стверджував
          # "БЛОКУЄ Production", але код блокував ЛИШЕ під WEB3_STRICT_MODE — тобто
          # prod-деплой, що забув прапор, лишав mint-triggering endpoint відкритим.
          # Тепер raise і в prod незалежно від прапора.
          if ENV["WEB3_STRICT_MODE"] == "true" || Rails.env.production?
            raise SecurityError,
                  "CHAINLINK_HMAC_SECRET обов'язковий у production / WEB3_STRICT_MODE. " \
                  "Oracle callback endpoint незахищений без HMAC верифікації."
          end

          Rails.logger.warn "⚠️ [Oracle Security] CHAINLINK_HMAC_SECRET не встановлено " \
                            "(dev/test — bypass із попередженням)."
          return
        end

        signature = request.headers["X-Chainlink-Signature"]

        if signature.blank?
          render json: { error: "Missing X-Chainlink-Signature header" }, status: :unauthorized
          return
        end

        body = request.raw_post
        expected = OpenSSL::HMAC.hexdigest("SHA256", hmac_secret, body)

        unless ActiveSupport::SecurityUtils.secure_compare(expected, signature)
          Rails.logger.error "🚨 [Oracle Security] Invalid HMAC signature for oracle callback. " \
                             "Possible forgery attempt."
          render json: { error: "Invalid HMAC signature" }, status: :unauthorized
        end
      end

      # [SCALE]: telemetry_logs is PARTITION BY RANGE (created_at).
      # When created_at is provided in the callback, PostgreSQL prunes to a single
      # partition instead of scanning chainlink_request_id indexes across all partitions.
      # At billions of rows this is the difference between O(log N) and O(P × log N).
      def find_telemetry_log(request_id)
        # [S6.16] pruning-логіка (1с-вікно + degraded-облік) — One-Home
        # `TelemetryLog.partition_pruned`. Якщо missing-лічильник зростає —
        # Chainlink DON має передавати created_at (Functions JS source + config).
        TelemetryLog.where(chainlink_request_id: request_id)
                    .partition_pruned(params[:created_at], metric_caller: "OracleCallbacksController")
                    .order(created_at: :desc)
                    .first!
      end
    end
  end
end
