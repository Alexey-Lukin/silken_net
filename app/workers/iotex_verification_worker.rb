# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class IotexVerificationWorker
  include ApplicationWeb3Worker
  include Web3CircuitBreaker
  sidekiq_options queue: "web3_critical", retry: 5

  # [INF.22] Вичерпані ретраї більше не тонуть МОВЧКИ. Recovery тут поки ручний
  # (`IotexBackfillWorker`-крона не існує — [`00_07`](00_07_Action_Plan_Tracker) INF.22),
  # а ручний re-enqueue потребує ОБОХ аргументів: `TelemetryLog` партиційований, тож
  # без `created_at` його не резолвити (`find_telemetry_log_with_pruning`). Доти в Dead
  # Set лягала джоба, чиєї адреси в логах не було взагалі — тобто оголошений спосіб
  # відновлення був недосяжний саме тоді, коли ставав потрібен.
  # ⚠️ Хук навмисно нічого не кидає й не мутує: `sidekiq_retries_exhausted` НЕ retry-able
  # (Sidekiq ловить виняток і однаково робить `send_to_morgue`), тож raise усередині лише
  # обірвав би слід, заради якого хук і ставиться [ARCH.67].
  sidekiq_retries_exhausted do |job, exception|
    log_id, created_at_iso = job["args"]
    Rails.logger.warn "🛑 [IoTeX Exhausted] Верифікацію TelemetryLog ##{log_id} " \
                      "(created_at=#{created_at_iso}) вичерпано після всіх спроб: #{exception.message}. " \
                      "Re-enqueue вручну: IotexVerificationWorker.perform_async(#{log_id.inspect}, #{created_at_iso.inspect})."
  end

  def perform(telemetry_log_id, created_at_iso)
    log = find_telemetry_log_with_pruning(telemetry_log_id, created_at_iso, log_prefix: "[IoTeX]")
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
end
