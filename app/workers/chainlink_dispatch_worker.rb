# frozen_string_literal: true

class ChainlinkDispatchWorker
  include ApplicationWeb3Worker
  sidekiq_options queue: "web3_critical", retry: 5

  def perform(telemetry_log_id, created_at_iso)
    log = find_log(telemetry_log_id, created_at_iso)
    return unless log
    return Rails.logger.info "✅ [Chainlink] TelemetryLog ##{telemetry_log_id} вже відправлено до оракула." if log.chainlink_request_id.present?

    with_web3_error_handling("Chainlink", "TelemetryLog ##{telemetry_log_id}") do
      service = Chainlink::OracleDispatchService.new(log)
      service.dispatch!
    end

    Rails.logger.info "🔗 [Chainlink] TelemetryLog ##{telemetry_log_id} успішно диспетчеризовано."
  rescue Chainlink::OracleDispatchService::DispatchError => e
    Rails.logger.error "🚨 [Chainlink] Dispatch TelemetryLog ##{telemetry_log_id} зазнав невдачі: #{e.message}"
    raise
  end

  private

  def find_log(telemetry_log_id, created_at_iso)
    created_at = Time.iso8601(created_at_iso)
    log = TelemetryLog.find_by(id: telemetry_log_id, created_at: created_at)
    Rails.logger.error "🛑 [Chainlink] TelemetryLog ##{telemetry_log_id} не знайдено." unless log
    log
  rescue ArgumentError => e
    Rails.logger.error "🛑 [Chainlink] Некоректний формат created_at для TelemetryLog ##{telemetry_log_id}: #{e.message}"
    nil
  end
end
