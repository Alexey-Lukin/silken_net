# frozen_string_literal: true

class ChainlinkDispatchWorker
  include Sidekiq::Job
  sidekiq_options queue: "web3", retry: 5

  def perform(telemetry_log_id, created_at_iso)
    log = TelemetryLog.find_by(id: telemetry_log_id, created_at: Time.iso8601(created_at_iso))
    return Rails.logger.error "🛑 [Chainlink] TelemetryLog ##{telemetry_log_id} не знайдено." unless log
    return Rails.logger.info "✅ [Chainlink] TelemetryLog ##{telemetry_log_id} вже відправлено до оракула." if log.chainlink_request_id.present?

    service = Chainlink::OracleDispatchService.new(log)
    service.dispatch!

    Rails.logger.info "🔗 [Chainlink] TelemetryLog ##{telemetry_log_id} успішно диспетчеризовано."
  rescue Chainlink::OracleDispatchService::DispatchError => e
    Rails.logger.error "🚨 [Chainlink] Dispatch TelemetryLog ##{telemetry_log_id} зазнав невдачі: #{e.message}"
    raise e
  end
end
