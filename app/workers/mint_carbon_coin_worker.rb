# frozen_string_literal: true

class MintCarbonCoinWorker
  include Sidekiq::Job
  sidekiq_options queue: "web3", retry: 5

  # МЕ NAM-TAR: Фінальний Ролбек
  sidekiq_retries_exhausted do |msg, _ex|
    transaction_id = msg["args"].first
    tx = BlockchainTransaction.find_by(id: transaction_id)

    if tx
      Rails.logger.fatal "☠️ [Web3] Капітуляція. Транзакція ##{transaction_id} скасована. Повернення активів..."

      ActiveRecord::Base.transaction do
        tx.update!(status: :failed, notes: "Rollback: Вичерпано спроби підключення до Polygon.")
        
        # [ВИПРАВЛЕНО]: Конвертуємо токени назад у бали росту
        # Використовуємо константу з EvaluatorWorker для точності
        refund_points = (tx.amount * TokenomicsEvaluatorWorker::EMISSION_THRESHOLD).to_i
        tx.wallet.increment!(:balance, refund_points)
      end
    end
  end

  def perform(blockchain_transaction_id)
    tx = BlockchainTransaction.find_by(id: blockchain_transaction_id)
    return unless tx
    
    # Захист від повторного запуску підтверджених транзакцій
    return if tx.status_confirmed?

    Rails.logger.info "🚀 [Web3] Старт мінтингу для #{tx.token_type}: #{tx.amount} одиниць."

    # Виклик сервісу, який тепер підтримує стан :processing
    BlockchainMintingService.call(blockchain_transaction_id)

  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn "⚠️ [Web3] Транзакцію ##{blockchain_transaction_id} не знайдено."
  rescue StandardError => e
    # Повертаємо в :pending, щоб наступний retry міг спробувати знову
    BlockchainTransaction.find_by(id: blockchain_transaction_id)&.update!(status: :pending)

    Rails.logger.error "🚨 [Web3] Помилка RPC: #{e.message}. Sidekiq планує переповтор."
    raise e
  end
end
