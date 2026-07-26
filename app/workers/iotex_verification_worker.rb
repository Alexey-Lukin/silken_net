# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class IotexVerificationWorker
  include ApplicationWeb3Worker
  include Web3CircuitBreaker
  sidekiq_options queue: "web3_critical", retry: 5

  def perform(telemetry_log_id, created_at_iso)
    log = find_log(telemetry_log_id, created_at_iso)
    return unless log

    # [ARCH.53/B1] Recover lost Chainlink-dispatch enqueue: краш між update!(verified) і
    # ChainlinkDispatchWorker.perform_async лишав би лог застрендженим — цей guard на retry
    # робив early-return → dispatch ніколи не enqueue (recovery-крони нема). Якщо верифіковано,
    # але dispatch не стартував (chainlink_request_id nil + oracle pending) → переenqueue
    # (ідемпотентно: ChainlinkDispatchWorker guard'иться на chainlink_request_id.present?).
    if log.verified_by_iotex?
      if log.chainlink_request_id.blank? && log.oracle_status_pending?
        ChainlinkDispatchWorker.perform_async(telemetry_log_id, created_at_iso)
        return Rails.logger.warn "🔁 [IoTeX] TelemetryLog ##{telemetry_log_id} верифіковано, але dispatch загубився — переenqueue."
      end
      return Rails.logger.info "✅ [IoTeX] TelemetryLog ##{telemetry_log_id} вже верифіковано."
    end

    with_circuit_breaker("iotex_w3bstream") do
      with_web3_error_handling("IoTeX", "TelemetryLog ##{telemetry_log_id}") do
        service = Iotex::W3bstreamVerificationService.new(log)
        zk_proof_ref = service.verify!

        log.update!(verified_by_iotex: true, zk_proof_ref: zk_proof_ref)

        # 🔗 [Chainlink]: Після успішної верифікації IoTeX — диспетчеризуємо до Chainlink Oracle
        ChainlinkDispatchWorker.perform_async(telemetry_log_id, created_at_iso)

        Rails.logger.info "🔐 [IoTeX] TelemetryLog ##{telemetry_log_id} верифіковано. Proof: #{zk_proof_ref}"
      end
    end
  rescue Web3CircuitBreaker::CircuitOpenError
    Rails.logger.warn "⚡ [IoTeX] Circuit OPEN — TelemetryLog ##{telemetry_log_id} буде повторено пізніше."
    raise
  rescue Iotex::W3bstreamVerificationService::VerificationError => e
    Rails.logger.error "🚨 [IoTeX] Верифікація TelemetryLog ##{telemetry_log_id} зазнала невдачі: #{e.message}"
    raise
  end

  private

  # [P1 FIX]: Аналогічно ChainlinkDispatchWorker — перехоплюємо ArgumentError
  # від Time.iso8601 при некоректному форматі рядка, щоб не витрачати ретраї даремно.
  def find_log(telemetry_log_id, created_at_iso)
    created_at = Time.iso8601(created_at_iso)
    log = TelemetryLog.find_by(id: telemetry_log_id, created_at: created_at)
    Rails.logger.error "🛑 [IoTeX] TelemetryLog ##{telemetry_log_id} не знайдено." unless log
    log
  rescue ArgumentError => e
    Rails.logger.error "🛑 [IoTeX] Некоректний формат created_at для TelemetryLog ##{telemetry_log_id}: #{e.message}"
    nil
  end
end
