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
    # Якщо ми працювали з батчем, дістаємо масив ID, якщо з одиничною — ID.
    tx_ids = msg["args"].flatten.compact
    txs = BlockchainTransaction.where(id: tx_ids)

    txs.each do |tx|
      next unless tx.status_pending? || tx.status_processing?

      Rails.logger.fatal "☠️ [Web3] Капітуляція транзакції ##{tx.id}. Запуск протоколу повернення активів..."

      ActiveRecord::Base.transaction do
        # Pessimistic lock для запобігання подвійного використання балів під час відкату
        tx.wallet.with_lock do
          # Відновлюємо внутрішній баланс Солдата (бали)
          threshold = TokenomicsEvaluatorWorker::EMISSION_THRESHOLD
          refund_points = (tx.amount * threshold).to_i

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

  # [ОПТИМІЗАЦІЯ]: Тепер perform може приймати як один ID, так і масив, 
  # або взагалі нічого (тоді він забере всі pending транзакції).
  def perform(blockchain_transaction_ids = nil)
    # 1. ЗБІР РОБОТИ (The Harvest)
    # Якщо ID не передані, беремо чергу pending транзакцій (ліміт 1000 для стабільності пам'яті)
    tx_ids = Array(blockchain_transaction_ids).presence || 
             BlockchainTransaction.pending.limit(1000).pluck(:id)

    return if tx_ids.empty?

    # 2. [SLICING]: ДРОБОВИК ДЛЯ ГАЗУ (Gas Limit optimization)
    # Розбиваємо масив на групи по 200 вузлів. Це гарантує, що ми не 
    # перевищимо Gas Limit блоку Polygon при виклику batchMint.
    tx_ids.each_slice(200) do |batch|
      process_batch(batch)
    end
  end

  private

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

    Rails.logger.error "🚨 [Web3] Batch RPC Error: #{e.message}. Планується повтор..."
    raise e
  end
end
