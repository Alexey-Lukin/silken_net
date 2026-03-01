# frozen_string_literal: true

class MintCarbonCoinWorker
  include Sidekiq::Job
  # Використовуємо чергу web3 з низьким пріоритетом, щоб не блокувати телеметрію.
  # Обмеження ретраїв до 5 запобігає нескінченному спаму в RPC Polygon.
  sidekiq_options queue: "web3", retry: 5

  # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
  # МЕ NAM-TAR: Фінальний Ролбек (The Absolute Integrity)
  # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
  # Викликається, коли всі 5 спроб RPC-зв'язку вичерпано. 
  # Ми не можемо дозволити капіталу "зависнути" в ефірі.
  sidekiq_retries_exhausted do |msg, _ex|
    tx_id = msg["args"].first
    tx = BlockchainTransaction.find_by(id: tx_id)

    if tx && (tx.status_pending? || tx.status_processing?)
      Rails.logger.fatal "☠️ [Web3] Капітуляція транзакції ##{tx_id}. Запуск протоколу повернення активів..."

      ActiveRecord::Base.transaction do
        # Pessimistic lock для запобігання подвійного використання балів під час відкату
        tx.wallet.with_lock do
          # Відновлюємо внутрішній баланс Солдата (бали)
          # Використовуємо константу емісії для точного розрахунку повернення
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

  def perform(blockchain_transaction_id)
    tx = BlockchainTransaction.includes(wallet: :tree).find_by(id: blockchain_transaction_id)
    return unless tx

    # [Idempotency Guard]: Захист від повторного мінтингу вже закритих транзакцій
    return if tx.status_confirmed? || tx.status_failed?

    # Блокуємо запис транзакції для запобігання Race Conditions між воркерами
    tx.with_lock do
      return if tx.status_processing? 
      tx.update!(status: :processing)
    end

    Rails.logger.info "🚀 [Web3] Початок емісії #{tx.token_type} (#{tx.amount} SCC/SFC) для #{tx.to_address}"

    # Виклик сервісу взаємодії зі смарт-контрактом.
    # Сервіс загартований для роботи з Polygon та трансляції статусів через Turbo Streams.
    BlockchainMintingService.call(tx.id)

  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn "⚠️ [Web3] Транзакція ##{blockchain_transaction_id} випала з Матриці."
  rescue StandardError => e
    # Якщо сталася помилка на рівні RPC, повертаємо статус у Pending,
    # щоб наступний ретрай Sidekiq почав із чистого листа.
    tx&.update!(
      status: :pending, 
      notes: "Retry: #{e.message.truncate(200)} [At: #{Time.current}]"
    )

    Rails.logger.error "🚨 [Web3] RPC Error (TX: #{blockchain_transaction_id}): #{e.message}. Планується повтор..."
    raise e # Прокидаємо помилку далі, щоб Sidekiq зробив retry
  end
end
