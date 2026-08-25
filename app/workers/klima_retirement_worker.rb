# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class KlimaRetirementWorker
  include ApplicationWeb3Worker
  # Web3 Low транзакції — черга web3_low (пріоритет 1), бо це не критична операція,
  # а фінансова дія з ESG-звітності, яка може зачекати.
  sidekiq_options queue: "web3_low", retry: 3

  # [ARCH.95] Параметр названий одиницею. Sidekiq-аргументи позиційні, тож kwarg
  # сервісу сюди не дотягується — а саме цей рядок і є місцем, де майбутній
  # enqueue-викликач передасть число. Ім'я `amount` не казало НІЧОГО про те, бали
  # це чи монети, і рівно ця німота коштувала класу ARCH.95.
  def perform(wallet_id, scc_amount)
    wallet = Wallet.find_by(id: wallet_id)

    unless wallet
      Rails.logger.error "🛑 [KlimaDAO] Wallet ##{wallet_id} не знайдено."
      return
    end

    with_web3_error_handling("KlimaDAO", "Wallet ##{wallet_id}") do
      KlimaDao::RetirementService.new(wallet, scc: scc_amount).retire_carbon!
    end

    Rails.logger.info "🌿 [KlimaDAO] Retirement Worker завершив погашення #{scc_amount} SCC для Wallet ##{wallet_id}."
  rescue KlimaDao::RetirementService::InsufficientBalanceError => e
    Rails.logger.warn "⚠️ [KlimaDAO] Недостатньо коштів для Wallet ##{wallet_id}: #{e.message}"
  rescue KlimaDao::RetirementService::InvalidTokenTypeError => e
    Rails.logger.warn "⚠️ [KlimaDAO] Невірний тип токена для Wallet ##{wallet_id}: #{e.message}"
  rescue StandardError => e
    Rails.logger.error "🚨 [KlimaDAO] Помилка погашення для Wallet ##{wallet_id}: #{e.message}"
    raise
  end
end
