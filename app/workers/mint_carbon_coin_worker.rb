# SPDX-License-Identifier: AGPL-3.0-or-later
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
      # [S6.16] status-скан — свідомо без `created_at`-межі (підстава там сама, що
      # в `process_pending_transactions`: reset-to-pending тримає старий created_at).
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
    Rails.logger.warn "⚡ [Polygon] Circuit OPEN — мінтинг буде повторено пізніше."
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

    # [S6.16] `created_at` беремо тим самим SELECT'ом, що й id — не щоб фільтрувати
    # (сам `status`-скан прунити НЕ можна, підстава в `process_pending_transactions`),
    # а щоб віддати його далі партиційною підказкою. Без нього кожен батч перебирав
    # усі партиції наново.
    rows = wallet.blockchain_transactions.status_pending.pluck(:id, :created_at)
    return if rows.empty?

    Rails.logger.info "🔐 [Web3] Trustless мінтинг для TelemetryLog ##{telemetry_log_id}: #{rows.size} транзакцій..."

    rows.each_slice(100) do |slice|
      within_rpc_limit do
        BlockchainMintingService.call_batch(
          slice.map(&:first), telemetry_log: log, created_at_span: slice.map(&:last)
        )
      end
    end

  rescue StandardError => e
    Rails.logger.error "🚨 [Web3] Oracle-driven mint error для TelemetryLog ##{telemetry_log_id}: #{e.message}"
    raise
  end

  # [FALLBACK]: Auto-discovery pending транзакцій (cron або ручний запуск).
  # Працює без telemetry_log — для існуючого TokenomicsEvaluatorWorker flow.
  # [S6.16 / ARCH.52] Цей скан свідомо БЕЗ `created_at`-межі, і це не недогляд:
  # reset-to-pending робить raw `update_all :processing→:pending`, лишаючи СТАРИЙ
  # `created_at`, тож нижня межа осиротила б саме застряглі кошти. Правильний
  # важіль для status-скану — partial index (`(status, created_at) WHERE status
  # IN (0,1)`), він уже стоїть. Прунимо натомість усе, що ПІСЛЯ нього: там id
  # уже відомі, тож несемо їхній `created_at`-span далі.
  def process_pending_transactions
    rows = BlockchainTransaction.status_pending.limit(1000).pluck(:id, :created_at)
    return if rows.empty?

    rows.each_slice(100) do |slice|
      process_batch(slice.map(&:first), slice.map(&:last))
    end
  end

  def process_batch(batch_ids, span)
    # [Idempotency & Race Condition Guard]
    # Використовуємо спливаючий статус :processing для блокування батчу
    txs = pruned_batch(batch_ids, span).where(status: :pending)
    return if txs.empty?

    Rails.logger.info "🚀 [Web3] Запуск батч-емісії для #{txs.size} транзакцій..."

    # [RATE LIMITED + ЧАСОВИЙ ПАРАДОКС]: RPC виклик захищений глобальним лімітером.
    # BlockchainMintingService.call_batch працює через .transact (асинхронно),
    # цей виклик повернеться миттєво. Sidekiq не буде висіти в очікуванні від Alchemy.
    within_rpc_limit do
      BlockchainMintingService.call_batch(txs.pluck(:id), created_at_span: span)
    end

  rescue StandardError => e
    # Якщо сталася помилка на рівні підключення до RPC, повертаємо статус у Pending,
    # щоб наступний ретрай Sidekiq спробував знову.
    pruned_batch(batch_ids, span).where(status: :processing)
                                 .update_all(status: :pending, notes: "Retry: #{e.message.truncate(150)}")

    # Оповіщаємо UI про поточну спробу, щоб користувач бачив прогрес у реальному часі
    pruned_batch(batch_ids, span).each do |tx|
      tx.wallet&.broadcast_balance_update
    end

    Rails.logger.error "🚨 [Web3] Batch RPC Error: #{e.message}. Планується повтор..."
    raise
  end

  # [S6.16] Свіжий relation на кожен виклик — не мемоїзований: rescue-гілка
  # читає ті самі рядки ПІСЛЯ того, як сервіс міг змінити їхній статус, тож
  # закешований load віддав би стару картину.
  def pruned_batch(batch_ids, span)
    BlockchainTransaction.where_ids_pruned(batch_ids, span, metric_caller: "MintCarbonCoinWorker")
  end

  # [COMPOSITE PK]: telemetry_logs партиціоновано по created_at.
  # Передача created_at дозволяє PostgreSQL пропустити непотрібні партиції.
  def find_telemetry_log(telemetry_log_id, created_at_iso)
    find_telemetry_log_with_pruning(telemetry_log_id, created_at_iso, log_prefix: "[Web3]")
  end
end
