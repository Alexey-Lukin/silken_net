# frozen_string_literal: true

class MintCarbonCoinWorker
  include Sidekiq::Job
  # Використовуємо чергу web3 з низьким пріоритетом, щоб не блокувати телеметрію.
  # Обмеження ретраїв до 5 запобігає нескінченному спаму в RPC Polygon.
  sidekiq_options queue: "web3", retry: 5

  # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
  # МЕ NAM-TAR: Фінальний Ролбек (The Absolute Integrity)
  # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
  # Викликається, коли всі 5 спроб RPC-зв'язку (відправки в мемпул) вичерпано.
  # Ми не можемо дозволити капіталу "зависнути" в ефірі.
  sidekiq_retries_exhausted do |msg, _ex|
    telemetry_log_id = msg["args"].first
    created_at_iso = msg["args"].second

    if telemetry_log_id
      # Oracle-driven flow: знаходимо TelemetryLog та пов'язані транзакції
      scope = TelemetryLog.where(id: telemetry_log_id)
      if created_at_iso.present?
        begin
          scope = scope.where(created_at: Time.iso8601(created_at_iso))
        rescue ArgumentError
          # Некоректний формат — шукаємо без partition pruning
        end
      end
      log = scope.first
      next unless log

      wallet = log.tree&.wallet
      next unless wallet

      txs = wallet.blockchain_transactions.where(status: [ :pending, :processing ])
    else
      # Auto-discovery flow: знаходимо всі заблоковані транзакції
      txs = BlockchainTransaction.where(status: [ :pending, :processing ]).limit(1000)
    end

    txs.each do |tx|
      Rails.logger.fatal "☠️ [Web3] Капітуляція транзакції ##{tx.id}. Запуск протоколу повернення активів..."

      ActiveRecord::Base.transaction do
        # Pessimistic lock для запобігання подвійного використання балів під час відкату
        tx.wallet.with_lock do
          # Повертаємо рівно ту кількість балів, яка була заблокована при створенні транзакції.
          # Використовуємо збережений snapshot locked_points замість перерахунку через
          # поточний EMISSION_THRESHOLD, який міг змінитись між створенням та ролбеком.
          refund_points = tx.locked_points || (tx.amount * TokenomicsEvaluatorWorker::EMISSION_THRESHOLD).to_i

          tx.wallet.increment!(:balance, refund_points)
          tx.update!(
            status: :failed,
            notes: "Rollback: Постійний збій RPC. Повернено #{refund_points} балів на баланс DID: #{tx.wallet.tree.did}"
          )
        end
      end

      # Сповіщаємо UI про фінальний провал транзакції
      tx.wallet.broadcast_update if tx.wallet.respond_to?(:broadcast_update)
    end
  end

  # [TRUSTLESS]: perform тепер приймає telemetry_log_id як основний аргумент
  # для oracle-driven flow (OracleCallbacksController передає log.id_value + created_at).
  # [COMPOSITE PK]: telemetry_logs партиціоновано по created_at, тому передаємо обидва
  # поля для ефективного partition pruning (O(log N) замість O(P × log N)).
  # Без аргументів — auto-discovery pending транзакцій (fallback/cron).
  def perform(telemetry_log_id = nil, created_at_iso = nil)
    if telemetry_log_id
      process_telemetry_log(telemetry_log_id, created_at_iso)
    else
      process_pending_transactions
    end
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

    tx_ids.each_slice(200) do |batch|
      BlockchainMintingService.call_batch(batch, telemetry_log: log)
    end

  rescue StandardError => e
    Rails.logger.error "🚨 [Web3] Oracle-driven mint error для TelemetryLog ##{telemetry_log_id}: #{e.message}"
    raise e
  end

  # [FALLBACK]: Auto-discovery pending транзакцій (cron або ручний запуск).
  # Працює без telemetry_log — для існуючого TokenomicsEvaluatorWorker flow.
  def process_pending_transactions
    tx_ids = BlockchainTransaction.status_pending.limit(1000).pluck(:id)
    return if tx_ids.empty?

    tx_ids.each_slice(200) do |batch|
      process_batch(batch)
    end
  end

  def process_batch(batch_ids)
    # [Idempotency & Race Condition Guard]
    # Використовуємо спливаючий статус :processing для блокування батчу
    txs = BlockchainTransaction.where(id: batch_ids).where(status: :pending)
    return if txs.empty?

    Rails.logger.info "🚀 [Web3] Запуск батч-емісії для #{txs.size} транзакцій..."

    # [ЧАСОВИЙ ПАРАДОКС]: Оскільки BlockchainMintingService.call_batch тепер
    # працює через .transact (асинхронно), цей виклик повернеться миттєво.
    # Sidekiq не буде висіти в очікуванні підтвердження від Alchemy.
    BlockchainMintingService.call_batch(txs.pluck(:id))

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
    raise e
  end

  # [COMPOSITE PK]: telemetry_logs партиціоновано по created_at.
  # Передача created_at дозволяє PostgreSQL пропустити непотрібні партиції.
  def find_telemetry_log(telemetry_log_id, created_at_iso)
    scope = TelemetryLog.where(id: telemetry_log_id)

    if created_at_iso.present?
      begin
        scope = scope.where(created_at: Time.iso8601(created_at_iso))
      rescue ArgumentError
        # Некоректний формат — шукаємо без partition pruning
      end
    end

    log = scope.first
    Rails.logger.error "🛑 [Web3] TelemetryLog ##{telemetry_log_id} не знайдено." unless log
    log
  end
end
