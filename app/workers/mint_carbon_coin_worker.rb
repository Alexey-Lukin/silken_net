# frozen_string_literal: true

class MintCarbonCoinWorker
  include ApplicationWeb3Worker
  include Web3CircuitBreaker
  # Web3 Critical черга — мінтинг є час-чутливою фінансовою операцією.
  # Обмеження ретраїв до 5 запобігає нескінченному спаму в RPC Polygon.
  sidekiq_options queue: "web3_critical", retry: 5

  # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
  # МЕ NAM-TAR: Фінальний Ролбек (The Absolute Integrity)
  # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
  # Викликається, коли всі 5 спроб RPC-зв'язку (відправки в мемпул) вичерпано.
  # Ми не можемо дозволити капіталу "зависнути" в ефірі.
  # [ARCHITECTURAL FIX]: Логіка ролбеку вилучена в MintingRollbackService
  # для дотримання принципу Single Responsibility та тестованості.
  sidekiq_retries_exhausted do |msg, _ex|
    telemetry_log_id = msg["args"].first
    created_at_iso = msg["args"].second

    if telemetry_log_id
      MintingRollbackService.call(
        telemetry_log_id: telemetry_log_id,
        created_at_iso: created_at_iso
      )
    else
      txs = BlockchainTransaction.where(status: [ :pending, :processing ]).limit(1000)
      MintingRollbackService.call(transactions: txs)
    end
  end

  # [TRUSTLESS]: perform тепер приймає telemetry_log_id як основний аргумент
  # для oracle-driven flow (OracleCallbacksController передає log.id_value + created_at).
  # [COMPOSITE PK]: telemetry_logs партиціоновано по created_at, тому передаємо обидва
  # поля для ефективного partition pruning (O(log N) замість O(P × log N)).
  # Без аргументів — auto-discovery pending транзакцій (fallback/cron).
  def perform(telemetry_log_id = nil, created_at_iso = nil)
    with_circuit_breaker("polygon_rpc") do
      if telemetry_log_id
        process_telemetry_log(telemetry_log_id, created_at_iso)
      else
        process_pending_transactions
      end
    end
  rescue Web3CircuitBreaker::CircuitOpenError
    Rails.logger.warn "⚡ [Polygon] Circuit OPEN — мінтинг TelemetryLog ##{telemetry_log_id || 'batch'} буде повторено пізніше."
    raise
  end

  private

  # [TRUSTLESS]: Oracle-driven мінтинг — знаходимо верифіковану телеметрію
  # та запускаємо мінтинг для pending транзакцій пов'язаного гаманця.
  def process_telemetry_log(telemetry_log_id, created_at_iso)
    log = find_telemetry_log(telemetry_log_id, created_at_iso)
    return unless log

    wallet = log.tree.wallet
    return unless wallet

    tx_ids = wallet.blockchain_transactions.status_pending.pluck(:id)
    return if tx_ids.empty?

    Rails.logger.info "🔐 [Web3] Trustless мінтинг для TelemetryLog ##{telemetry_log_id}: #{tx_ids.size} транзакцій..."

    tx_ids.each_slice(100) do |batch|
      within_rpc_limit do
        BlockchainMintingService.call_batch(batch, telemetry_log: log)
      end
    end

  rescue StandardError => e
    Rails.logger.error "🚨 [Web3] Oracle-driven mint error для TelemetryLog ##{telemetry_log_id}: #{e.message}"
    raise
  end

  # [FALLBACK]: Auto-discovery pending транзакцій (cron або ручний запуск).
  # Працює без telemetry_log — для існуючого TokenomicsEvaluatorWorker flow.
  def process_pending_transactions
    tx_ids = BlockchainTransaction.status_pending.limit(1000).pluck(:id)
    return if tx_ids.empty?

    tx_ids.each_slice(100) do |batch|
      process_batch(batch)
    end
  end

  def process_batch(batch_ids)
    # [Idempotency & Race Condition Guard]
    # Використовуємо спливаючий статус :processing для блокування батчу
    txs = BlockchainTransaction.where(id: batch_ids).where(status: :pending)
    return if txs.empty?

    Rails.logger.info "🚀 [Web3] Запуск батч-емісії для #{txs.size} транзакцій..."

    # [RATE LIMITED + ЧАСОВИЙ ПАРАДОКС]: RPC виклик захищений глобальним лімітером.
    # BlockchainMintingService.call_batch працює через .transact (асинхронно),
    # цей виклик повернеться миттєво. Sidekiq не буде висіти в очікуванні від Alchemy.
    within_rpc_limit do
      BlockchainMintingService.call_batch(txs.pluck(:id))
    end

  rescue StandardError => e
    # Якщо сталася помилка на рівні підключення до RPC, повертаємо статус у Pending,
    # щоб наступний ретрай Sidekiq спробував знову.
    BlockchainTransaction.where(id: batch_ids, status: :processing)
                         .update_all(status: :pending, notes: "Retry: #{e.message.truncate(150)}")

    # Оповіщаємо UI про поточну спробу, щоб користувач бачив прогрес у реальному часі
    BlockchainTransaction.where(id: batch_ids).each do |tx|
      tx.wallet&.broadcast_balance_update
    end

    Rails.logger.error "🚨 [Web3] Batch RPC Error: #{e.message}. Планується повтор..."
    raise
  end

  # [COMPOSITE PK]: telemetry_logs партиціоновано по created_at.
  # Передача created_at дозволяє PostgreSQL пропустити непотрібні партиції.
  def find_telemetry_log(telemetry_log_id, created_at_iso)
    find_telemetry_log_with_pruning(telemetry_log_id, created_at_iso, log_prefix: "[Web3]")
  end
end
