# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class StreamrBroadcastWorker
  include ApplicationWeb3Worker
  sidekiq_options queue: "low", retry: 3

  def perform(telemetry_log_id, created_at_iso)
    # [S6.16] Пошук — через One-Home `find_telemetry_log_with_pruning` (1с-вікно
    # + облік degraded-шляху). Рукописна точна рівність, що стояла тут, збігалася
    # лише з мікросекундним ISO і мовчки давала nil на секундному — а тут навіть
    # rescue ArgumentError не було, тож битий рядок з'їдав усі три ретраї.
    log = find_telemetry_log_with_pruning(telemetry_log_id, created_at_iso, log_prefix: "[Streamr]")
    return unless log

    service = Streamr::BroadcasterService.new(log)
    service.broadcast!

    Rails.logger.info "📡 [Streamr] TelemetryLog ##{telemetry_log_id} транслювано в мережу Streamr."
  rescue Streamr::BroadcasterService::BroadcastError => e
    # Streamr — це потік присутності, а не фінансовий консенсус.
    # Якщо Streamr недоступний — логуємо помилку та НЕ перекидаємо далі.
    # Це гарантує, що основний pipeline (IoTeX → Chainlink) не постраждає.
    Rails.logger.error "🔇 [Streamr] Трансляція TelemetryLog ##{telemetry_log_id} зазнала невдачі: #{e.message}"

    # [E.50→INF.26] Діагностичний лічильник збоїв (НЕ «для alerting» — правило
    # зʼявиться лише з live-флотом, що дасть failure-rate ненульовий базлайн;
    # поріг над нулем був би шумом — декларація ярусу в docstring метрики).
    SilkenNet::Metrics::STREAMR_BROADCAST_FAILURES_TOTAL.increment
  end
end
