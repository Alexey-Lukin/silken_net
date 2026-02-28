# frozen_string_literal: true

class MintCarbonCoinWorker
  include Sidekiq::Job
  sidekiq_options queue: "web3", retry: 5

  # МЕ NAM-TAR: Фінальний Ролбек (The Safety Net)
  # Викликається, коли всі 5 спроб відправити транзакцію в Polygon провалилися.
  sidekiq_retries_exhausted do |msg, _ex|
    transaction_id = msg["args"].first
    tx = BlockchainTransaction.find_by(id: transaction_id)

    if tx && tx.status_pending? || tx.status_processing?
      Rails.logger.fatal "☠️ [Web3] Капітуляція. Транзакція ##{transaction_id} скасована. Повернення активів..."

      ActiveRecord::Base.transaction do
        # Блокуємо гаманець для безпечного повернення балів
        tx.wallet.lock!
        
        # [СИНХРОНІЗОВАНО]: Використовуємо поріг для точного відновлення балансу
        # Припускаємо, що EMISSION_THRESHOLD визначено в базовому модулі SilkenNet
        threshold = TokenomicsEvaluatorWorker::EMISSION_THRESHOLD
        refund_points = (tx.amount * threshold).to_i
        
        tx.wallet.increment!(:balance, refund_points)
        tx.update!(status: :failed, notes: "Rollback: Помилка RPC після 5 спроб. Повернено #{refund_points} балів.")
      end
    end
  end

  def perform(blockchain_transaction_id)
    tx = BlockchainTransaction.find_by(id: blockchain_transaction_id)
    return unless tx
    
    # Захист від подвійного мінтингу (Idempotency Guard)
    return if tx.status_confirmed?

    # Переводимо в :processing, щоб заблокувати транзакцію для інших воркерів
    tx.update!(status: :processing) unless tx.status_processing?

    Rails.logger.info "🚀 [Web3] Старт мінтингу для #{tx.token_type}: #{tx.amount} одиниць. Адреса: #{tx.to_address}"

    # Виклик сервісу, який взаємодіє зі смарт-контрактом (через web3.rb або eth.rb)
    # Очікуємо, що сервіс поверне tx_hash або викине помилку
    BlockchainMintingService.call(tx.id)

  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn "⚠️ [Web3] Транзакцію ##{blockchain_transaction_id} не знайдено."
  rescue StandardError => e
    # Повертаємо в :pending, щоб наступний retry (Sidekiq) мав чистий статус
    tx&.update!(status: :pending, notes: "Retry: #{e.message.truncate(200)}")

    Rails.logger.error "🚨 [Web3] Помилка RPC: #{e.message}. Sidekiq планує переповтор."
    raise e
  end
end
