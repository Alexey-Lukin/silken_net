# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class ChainlinkDispatchWorker
  include ApplicationWeb3Worker
  include Web3CircuitBreaker
  sidekiq_options queue: "web3_critical", retry: 5

  def perform(telemetry_log_id, created_at_iso)
    log = find_telemetry_log_with_pruning(telemetry_log_id, created_at_iso, log_prefix: "[Chainlink]")
    return unless log
    return Rails.logger.info "✅ [Chainlink] TelemetryLog ##{telemetry_log_id} вже відправлено до оракула." if log.chainlink_request_id.present?

    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    # 🔴 [INF.26] Спостереження в `ensure` ВСЕРЕДИНІ breaker-блоку — і обидві межі несучі.
    #
    # Доти `.observe` стояв ПІСЛЯ блоку, тобто був недосяжний на будь-якому провалі:
    # гістограма міряла «латентність диспатчів, що ВДАЛИСЬ», називаючись «dispatch
    # latency». Survivorship bias у чистому вигляді — деградований Chainlink, що
    # таймаутить на 60 с, не додавав до p99 НІЧОГО, і панель показувала здорову
    # латентність саме під час аварії.
    #
    # ⊥ Але «спостерігати завжди» було б протилежною помилкою: `CircuitOpenError`
    # відмовляє за мікросекунди, і ті семпли ЗАНИЗИЛИ Б p99 — тобто наш власний
    # запобіжник малював би оракул швидшим, ніж він є. Circuit-open не є латентністю
    # оракула, тож `ensure` живе ВСЕРЕДИНІ breaker'а: коли той відмовляє, блок не
    # виконується взагалі й семпла немає.
    #
    # Отже гістограма міряє рівно те, про що питає її панель: скільки часу займає
    # СПРОБА дійти до оракула — успішна чи провальна.
    with_circuit_breaker("chainlink_functions") do
      begin
        with_web3_error_handling("Chainlink", "TelemetryLog ##{telemetry_log_id}") do
          service = Chainlink::OracleDispatchService.new(log)
          service.dispatch!
        end
      ensure
        duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
        SilkenNet::Metrics::ORACLE_DISPATCH_DURATION.observe(duration)
      end
    end

    Rails.logger.info "🔗 [Chainlink] TelemetryLog ##{telemetry_log_id} успішно диспетчеризовано."
  rescue Web3CircuitBreaker::CircuitOpenError
    Rails.logger.warn "⚡ [Chainlink] Circuit OPEN — TelemetryLog ##{telemetry_log_id} буде повторено пізніше."
    raise
  rescue Chainlink::OracleDispatchService::DispatchError => e
    Rails.logger.error "🚨 [Chainlink] Dispatch TelemetryLog ##{telemetry_log_id} зазнав невдачі: #{e.message}"
    raise
  end
end
