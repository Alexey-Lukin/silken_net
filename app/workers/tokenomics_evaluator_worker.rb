# frozen_string_literal: true

class TokenomicsEvaluatorWorker
  include Sidekiq::Job
  sidekiq_options queue: "default", retry: 3

  # Константа конвертації: 10,000 балів = 1 SCC
  EMISSION_THRESHOLD = 10_000

  def perform
    Rails.logger.info "⚖️ [NAM-ŠID] Запуск Емісійного Центру..."
    
    # [НОВЕ]: Лічильники для фінального звіту
    stats = { processed_wallets: 0, total_minted: 0 }

    # Використовуємо find_each для нульового переповнення RAM
    Wallet.where("balance >= ?", EMISSION_THRESHOLD).find_each do |wallet|
      begin
        # Розраховуємо кількість цілих токенів
        tokens_to_mint = (wallet.balance / EMISSION_THRESHOLD).to_i
        next if tokens_to_mint.zero?

        points_to_lock = tokens_to_mint * EMISSION_THRESHOLD

        # Виклик моделі з Row-level lock!
        wallet.lock_and_mint!(points_to_lock, EMISSION_THRESHOLD)

        stats[:processed_wallets] += 1
        stats[:total_minted] += tokens_to_mint

        Rails.logger.info "🌱 [Емісія] Tree #{wallet.tree.did}: #{tokens_to_mint} SCC (Locked #{points_to_lock} pts)"
      rescue StandardError => e
        Rails.logger.error "🛑 [Емісія] Збій для гаманця ##{wallet.id}: #{e.message}"
        next # Продовжуємо обробку інших гаманців
      end
    end

    Rails.logger.info "✅ [NAM-ŠID] Цикл завершено. Оброблено гаманців: #{stats[:processed_wallets]}, Випущено: #{stats[:total_minted]} SCC."
  end
end
