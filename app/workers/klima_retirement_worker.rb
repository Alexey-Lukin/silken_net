# frozen_string_literal: true

class KlimaRetirementWorker
  include Sidekiq::Job
  # Web3 транзакції — черга web3 (пріоритет 1), бо це не критична операція,
  # а фінансова дія з ESG-звітності, яка може зачекати.
  sidekiq_options queue: "web3", retry: 3

  def perform(wallet_id, amount)
    wallet = Wallet.find_by(id: wallet_id)

    unless wallet
      Rails.logger.error "🛑 [KlimaDAO] Wallet ##{wallet_id} не знайдено."
      return
    end

    KlimaDao::RetirementService.new(wallet, amount).retire_carbon!

    Rails.logger.info "🌿 [KlimaDAO] Retirement Worker завершив погашення #{amount} SCC для Wallet ##{wallet_id}."
  rescue KlimaDao::RetirementService::InsufficientBalanceError => e
    Rails.logger.warn "⚠️ [KlimaDAO] Недостатньо коштів для Wallet ##{wallet_id}: #{e.message}"
  rescue KlimaDao::RetirementService::InvalidTokenTypeError => e
    Rails.logger.warn "⚠️ [KlimaDAO] Невірний тип токена для Wallet ##{wallet_id}: #{e.message}"
  rescue StandardError => e
    Rails.logger.error "🚨 [KlimaDAO] Помилка погашення для Wallet ##{wallet_id}: #{e.message}"
    raise e
  end
end
