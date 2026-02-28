# frozen_string_literal: true

class TokenomicsEvaluatorWorker
  include Sidekiq::Job
  sidekiq_options queue: "default", retry: 3

  # [СИНХРОНІЗОВАНО]: Центральна константа емісії. 
  # Використовується також у MintCarbonCoinWorker для розрахунку ролбеку.
  EMISSION_THRESHOLD = 10_000

  def perform
    Rails.logger.info "⚖️ [NAM-ŠID] Запуск Емісійного Центру..."
    
    stats = { processed_wallets: 0, total_minted: 0 }

    # [ОПТИМІЗАЦІЯ]: Шукаємо гаманці тільки АКТИВНИХ дерев. 
    # Використовуємо find_each для стабільності RAM при масштабуванні до мільйонів вузлів.
    active_wallets_scope = Wallet.joins(:tree)
                                 .where(trees: { status: :active })
                                 .where("balance >= ?", EMISSION_THRESHOLD)

    active_wallets_scope.find_each do |wallet|
      begin
        # Розраховуємо кількість цілих токенів
        tokens_to_mint = (wallet.balance / EMISSION_THRESHOLD).to_i
        next if tokens_to_mint.zero?

        points_to_lock = tokens_to_mint * EMISSION_THRESHOLD

        # Виклик моделі з Row-level lock! (Pessimistic Locking всередині)
        # Передаємо поріг для верифікації розрахунків всередині моделі
        wallet.lock_and_mint!(points_to_lock, EMISSION_THRESHOLD)

        stats[:processed_wallets] += 1
        stats[:total_minted] += tokens_to_mint

        Rails.logger.debug "🌱 [Емісія] Tree #{wallet.tree.did}: Сформовано наказ на мінтинг #{tokens_to_mint} SCC."
      rescue StandardError => e
        # Якщо один гаманець збійнув (наприклад, через Lock Timeout), 
        # ми логуємо це, але не зупиняємо обробку всього лісу.
        Rails.logger.error "🛑 [Емісія] Збій для гаманця ##{wallet.id}: #{e.message}"
        next 
      end
    end

    Rails.logger.info "✅ [NAM-ŠID] Цикл завершено. Оброблено гаманців: #{stats[:processed_wallets]}, Випущено: #{stats[:total_minted]} SCC."
  end
end
