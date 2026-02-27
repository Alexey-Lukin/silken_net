# frozen_string_literal: true

class MintCarbonCoinWorker
  include Sidekiq::Job

  # Ізолюємо повільні блокчейн-запити в окремій черзі 'web3'.
  sidekiq_options queue: "web3", retry: 5

  # МЕ NAM-TAR: Цей блок виконається ТІЛЬКИ якщо всі 5 спроб провалилися
  sidekiq_retries_exhausted do |msg, _ex|
    transaction_id = msg["args"].first
    transaction = BlockchainTransaction.find_by(id: transaction_id)

    if transaction
      Rails.logger.fatal "☠️ [Web3] Всі 5 спроб мінтингу вичерпано. Транзакція ##{transaction_id} мертва. Виконуємо Rollback."

      ActiveRecord::Base.transaction do
        transaction.update!(status: :failed)
        
        # Повертаємо чесно зароблені бали назад на баланс дерева ТІЛЬКИ після повної поразки
        transaction.wallet.increment!(:balance, transaction.amount)
      end
    end
  end

  def perform(blockchain_transaction_id)
    Rails.logger.info "🚀 [Web3 Worker] Старт процесу мінтингу. Transaction ID: #{blockchain_transaction_id}"

    # Делегуємо всю складну криптографію нашому сервісу
    BlockchainMintingService.call(blockchain_transaction_id)

  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn "⚠️ [Web3 Worker] Транзакцію ##{blockchain_transaction_id} не знайдено. Скасування."
  rescue StandardError => e
    # Якщо Alchemy "чхнув", транзакція зависла у статусі :processing.
    # Ми маємо повернути її в :pending, щоб наступний retry зміг її підхопити!
    transaction = BlockchainTransaction.find_by(id: blockchain_transaction_id)
    transaction&.update!(status: :pending)

    Rails.logger.error "🚨 [Web3 Worker] Помилка: #{e.message}. Sidekiq планує retry."
    raise e
  end
end
