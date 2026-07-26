# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class StreamrBroadcastWorker
  include ApplicationWeb3Worker
  sidekiq_options queue: "low", retry: 3

  def perform(telemetry_log_id, created_at_iso)
    log = TelemetryLog.find_by(id: telemetry_log_id, created_at: Time.iso8601(created_at_iso))
    return Rails.logger.warn "⚠️ [Streamr] TelemetryLog ##{telemetry_log_id} не знайдено." unless log

    service = Streamr::BroadcasterService.new(log)
    service.broadcast!

    Rails.logger.info "📡 [Streamr] TelemetryLog ##{telemetry_log_id} транслювано в мережу Streamr."
  rescue Streamr::BroadcasterService::BroadcastError => e
    # Streamr — це потік присутності, а не фінансовий консенсус.
    # Якщо Streamr недоступний — логуємо помилку та НЕ перекидаємо далі.
    # Це гарантує, що основний pipeline (IoTeX → Chainlink) не постраждає.
    Rails.logger.error "🔇 [Streamr] Трансляція TelemetryLog ##{telemetry_log_id} зазнала невдачі: #{e.message}"

    # [E.50 FIX]: Increment Prometheus counter для alerting при масових збоях.
    SilkenNet::Metrics::STREAMR_BROADCAST_FAILURES_TOTAL.increment
  end
end
