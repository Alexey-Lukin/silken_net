# frozen_string_literal: true

class IotexVerificationWorker
  include Sidekiq::Job
  sidekiq_options queue: "web3", retry: 5

  def perform(telemetry_log_id, created_at_iso)
    log = TelemetryLog.find_by(id: telemetry_log_id, created_at: Time.iso8601(created_at_iso))
    return Rails.logger.error "🛑 [IoTeX] TelemetryLog ##{telemetry_log_id} не знайдено." unless log
    return Rails.logger.info "✅ [IoTeX] TelemetryLog ##{telemetry_log_id} вже верифіковано." if log.verified_by_iotex?

    service = Iotex::W3bstreamVerificationService.new(log)
    zk_proof_ref = service.verify!

    log.update!(verified_by_iotex: true, zk_proof_ref: zk_proof_ref)

    # 🔗 [Chainlink]: Після успішної верифікації IoTeX — диспетчеризуємо до Chainlink Oracle
    ChainlinkDispatchWorker.perform_async(telemetry_log_id, created_at_iso)

    Rails.logger.info "🔐 [IoTeX] TelemetryLog ##{telemetry_log_id} верифіковано. Proof: #{zk_proof_ref}"
  rescue Iotex::W3bstreamVerificationService::VerificationError => e
    Rails.logger.error "🚨 [IoTeX] Верифікація TelemetryLog ##{telemetry_log_id} зазнала невдачі: #{e.message}"
    raise e
  end
end
