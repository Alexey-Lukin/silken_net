# frozen_string_literal: true

class TokenomicsEvaluatorWorker
  include Sidekiq::Job
  # Використовуємо чергу за замовчуванням, але з низьким пріоритетом відносно телеметрії
  sidekiq_options queue: "default", retry: 3

  # [СИНХРОНІЗОВАНО]: 1 SCC = 10,000 балів гомеостазу
  EMISSION_THRESHOLD = 10_000

  def perform
    Rails.logger.info "⚖️ [NAM-ŠID] Початок аудиту емісії..."
    
    stats = { wallets_scanned: 0, minted_count: 0, errors: 0 }

    # Вибираємо тільки тих Солдатів, які накопичили достатньо "життя" для емісії
    eligible_wallets = Wallet.joins(:tree)
                             .where(trees: { status: :active })
                             .where("balance >= ?", EMISSION_THRESHOLD)

    eligible_wallets.find_each do |wallet|
      stats[:wallets_scanned] += 1
      
      begin
        # Атомарна операція всередині моделі Wallet
        tokens_to_mint = (wallet.balance / EMISSION_THRESHOLD).to_i
        next if tokens_to_mint.zero?

        points_to_lock = tokens_to_mint * EMISSION_THRESHOLD

        # [LOCKING]: Виклик lock_and_mint! має обгортати списання балів 
        # та створення BlockchainTransaction в одну БД-транзакцію.
        wallet.lock_and_mint!(points_to_lock, EMISSION_THRESHOLD)

        stats[:minted_count] += tokens_to_mint
      rescue StandardError => e
        stats[:errors] += 1
        Rails.logger.error "🛑 [NAM-ŠID] Помилка гаманця Tree #{wallet.tree&.did}: #{e.message}"
        # Ми продовжуємо обробку лісу, незважаючи на падіння одного вузла
      end
    end

    log_final_stats(stats)
  end

  private

  def log_final_stats(stats)
    Rails.logger.info <<~LOG
      ✅ [NAM-ŠID] Аудит завершено.
      - Перевірено гаманців: #{stats[:wallets_scanned]}
      - Випущено токенів: #{stats[:minted_count]} SCC
      - Збоїв: #{stats[:errors]}
    LOG
  end
end
