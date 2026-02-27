# frozen_string_literal: true

class TokenomicsEvaluatorWorker
  include Sidekiq::Job
  # Використовуємо стандартну чергу, запускатиметься по cron-у (напр. раз на годину)
  sidekiq_options queue: "default", retry: 3

  # Константа конвертації: 10,000 балів емісії (growth_points) = 1 SCC (Carbon Coin)
  EMISSION_THRESHOLD = 10_000

  def perform
    Rails.logger.info "⚖️ [NAM-ŠID] Запуск Емісійного Центру. Оцінка балансів..."

    # Використовуємо find_each (батчинг на рівні SQL) для нульового переповнення RAM
    # Шукаємо тільки ті гаманці, де баланс досяг або перевищив поріг
    Wallet.where("balance >= ?", EMISSION_THRESHOLD).find_each do |wallet|
      evaluate_wallet(wallet)
    end

    Rails.logger.info "✅ [NAM-ŠID] Емісійний цикл завершено."
  end

  private

  def evaluate_wallet(wallet)
    # Розраховуємо, скільки цілих токенів ми можемо випустити
    tokens_to_mint = wallet.balance / EMISSION_THRESHOLD
    return if tokens_to_mint.zero?

    points_to_lock = tokens_to_mint * EMISSION_THRESHOLD

    # ТРАНЗАКЦІЙНІСТЬ (Абсолютна Істина):
    # Ми викликаємо інкапсульований метод моделі Wallet, який використовує .lock! 
    # Це гарантує, що бали не будуть списані двічі при паралельних запитах.
    wallet.lock_and_mint!(points_to_lock, EMISSION_THRESHOLD)

    Rails.logger.info "🌱 [Емісія] Дерево #{wallet.tree.did} конвертувало #{points_to_lock} балів у #{tokens_to_mint} SCC."

  rescue StandardError => e
    Rails.logger.error "🛑 [Емісія] Збій конвертації для гаманця #{wallet.id}: #{e.message}"
  end
end
