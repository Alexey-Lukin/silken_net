# frozen_string_literal: true

class MintCarbonCoinWorker
  include Sidekiq::Job
  # Використовуємо чергу web3 з низьким пріоритетом, щоб не блокувати телеметрію
  sidekiq_options queue: "web3", retry: 5

  # МЕ NAM-TAR: Фінальний Ролбек
  # Викликається, коли всі спроби RPC-зв'язку вичерпано.
  sidekiq_retries_exhausted do |msg, _ex|
    tx_id = msg["args"].first
    tx = BlockchainTransaction.find_by(id: tx_id)

    if tx && (tx.status_pending? || tx.status_processing?)
      Rails.logger.fatal "☠️ [Web3] Капітуляція транзакції ##{tx_id}. Запуск протоколу повернення активів..."

      ActiveRecord::Base.transaction do
        # Блокуємо гаманець для запобігання подвійного використання балів
        tx.wallet.with_lock do
          # Відновлюємо внутрішній баланс Солдата (бали)
          threshold = TokenomicsEvaluatorWorker::EMISSION_THRESHOLD
          refund_points = (tx.amount * threshold).to_i
          
          tx.wallet.increment!(:balance, refund_points)
          tx.update!(
            status: :failed, 
            notes: "Rollback: RPC Failure. Повернено #{refund_points} балів на баланс DID: #{tx.wallet.tree.did}"
          )
        end
      end
    end
  end

  def perform(blockchain_transaction_id)
    tx = BlockchainTransaction.find_by(id: blockchain_transaction_id)
    return unless tx

    # [Idempotency Guard]: Не мінтимо те, що вже підтверджено або провалено
    return if tx.status_confirmed? || tx.status_failed?

    # Блокуємо запис транзакції для поточного воркера
    tx.with_lock do
      return if tx.status_processing? # Захист від подвійного виконання
      tx.update!(status: :processing)
    end

    Rails.logger.info "🚀 [Web3] Мінтинг #{tx.token_type} (v.#{tx.amount}) -> #{tx.to_address}"

    # Виклик сервісу взаємодії зі смарт-контрактом.
    # Сервіс має бути ідемпотентним (перевіряти tx_hash у себе)
    BlockchainMintingService.call(tx.id)

  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn "⚠️ [Web3] Транзакція ##{blockchain_transaction_id} випала з матриці."
  rescue StandardError => e
    # Повертаємо в pending, щоб наступний retry міг почати з чистого листа
    tx&.update!(status: :pending, notes: "Retry: #{e.message.truncate(200)}")
    
    Rails.logger.error "🚨 [Web3] RPC Error: #{e.message}. Планується ретрай..."
    raise e # Sidekiq перехопить і запланує повтор
  end
end
