# frozen_string_literal: true

class MintCarbonCoinWorker
  include Sidekiq::Job

  # Ізолюємо повільні блокчейн-запити в окремій черзі 'web3'.
  # retry: 5 означає, що у разі відмови RPC-ноди (Alchemy) або стрибка ціни на газ,
  # Sidekiq автоматично спробує ще раз з експоненційною затримкою (через 15с, 1хв, 3хв і т.д.).
  sidekiq_options queue: "web3", retry: 5

  def perform(blockchain_transaction_id)
    Rails.logger.info "🚀 [Web3 Worker] Старт процесу мінтингу. Transaction ID: #{blockchain_transaction_id}"

    # Делегуємо всю складну криптографію нашому сервісу
    BlockchainMintingService.call(blockchain_transaction_id)

  rescue ActiveRecord::RecordNotFound
    # Якщо транзакцію з якоїсь причини видалили з бази до того, як воркер її взяв
    Rails.logger.warn "⚠️ [Web3 Worker] Транзакцію ##{blockchain_transaction_id} не знайдено. Скасування."
  rescue StandardError => e
    # Фіксуємо помилку в логах, але прокидаємо її далі (raise),
    # щоб Sidekiq зрозумів, що задача впала, і запланував retry.
    Rails.logger.error "🚨 [Web3 Worker] Помилка: #{e.message}"
    raise e
  end
end
