# frozen_string_literal: true

class KlimaRetirementWorker
  include ApplicationWeb3Worker
  # Web3 Low транзакції — черга web3_low (пріоритет 1), бо це не критична операція,
  # а фінансова дія з ESG-звітності, яка може зачекати.
  sidekiq_options queue: "web3_low", retry: 3

  def perform(wallet_id, amount)
    wallet = Wallet.find_by(id: wallet_id)

    unless wallet
      Rails.logger.error "🛑 [KlimaDAO] Wallet ##{wallet_id} не знайдено."
      return
    end

    with_web3_error_handling("KlimaDAO", "Wallet ##{wallet_id}") do
      KlimaDao::RetirementService.new(wallet, amount).retire_carbon!
    end

    Rails.logger.info "🌿 [KlimaDAO] Retirement Worker завершив погашення #{amount} SCC для Wallet ##{wallet_id}."
  rescue KlimaDao::RetirementService::InsufficientBalanceError => e
    Rails.logger.warn "⚠️ [KlimaDAO] Недостатньо коштів для Wallet ##{wallet_id}: #{e.message}"
  rescue KlimaDao::RetirementService::InvalidTokenTypeError => e
    Rails.logger.warn "⚠️ [KlimaDAO] Невірний тип токена для Wallet ##{wallet_id}: #{e.message}"
  rescue StandardError => e
    Rails.logger.error "🚨 [KlimaDAO] Помилка погашення для Wallet ##{wallet_id}: #{e.message}"
    raise
  end
end
