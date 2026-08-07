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

    with_circuit_breaker("chainlink_functions") do
      with_web3_error_handling("Chainlink", "TelemetryLog ##{telemetry_log_id}") do
        service = Chainlink::OracleDispatchService.new(log)
        service.dispatch!
      end
    end

    # [S2.4] Track oracle dispatch latency for Prometheus monitoring
    duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
    SilkenNet::Metrics::ORACLE_DISPATCH_DURATION.observe(duration)

    Rails.logger.info "🔗 [Chainlink] TelemetryLog ##{telemetry_log_id} успішно диспетчеризовано."
  rescue Web3CircuitBreaker::CircuitOpenError
    Rails.logger.warn "⚡ [Chainlink] Circuit OPEN — TelemetryLog ##{telemetry_log_id} буде повторено пізніше."
    raise
  rescue Chainlink::OracleDispatchService::DispatchError => e
    Rails.logger.error "🚨 [Chainlink] Dispatch TelemetryLog ##{telemetry_log_id} зазнав невдачі: #{e.message}"
    raise
  end
end
