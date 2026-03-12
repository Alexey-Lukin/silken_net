# frozen_string_literal: true

class TokenomicsEvaluatorWorker
  include ApplicationWeb3Worker
  # Використовуємо чергу за замовчуванням. Пріоритет нижчий за телеметрію,
  # оскільки фінансовий аудит може тривати довше.
  sidekiq_options queue: "default", retry: 3

  # [СИНХРОНІЗОВАНО]: 1 SCC (Silken Carbon Coin) = 10,000 балів гомеостазу.
  # Ця константа є фундаментом нашої токеноміки.
  EMISSION_THRESHOLD = 10_000

  def perform
    Rails.logger.info "⚖️ [NAM-ŠID] Початок глобального аудиту емісії..."

    stats = { wallets_scanned: 0, minted_count: 0, errors: 0 }
    # Колектор для ідентифікаторів транзакцій для подальшого групування (Batching)
    created_tx_ids = []

    # 1. СЕЛЕКЦІЯ: Вибираємо тільки активних Солдатів, чиї гаманці перетнули поріг емісії
    eligible_wallets = Wallet.joins(:tree)
                             .where(trees: { status: :active })
                             .where("balance >= ?", EMISSION_THRESHOLD)

    eligible_wallets.find_each do |wallet|
      stats[:wallets_scanned] += 1

      begin
        # Розраховуємо цілу кількість токенів, готову до випуску
        tokens_to_mint = (wallet.balance / EMISSION_THRESHOLD).to_i
        next if tokens_to_mint.zero?

        # Кількість балів, що будуть спалені в обмін на токени
        points_to_lock = tokens_to_mint * EMISSION_THRESHOLD

        # [LOCKING]: Виклик lock_and_mint! виконує атомарне списання балів у БД
        # та створює запис у BlockchainTransaction зі статусом :pending.
        tx = wallet.lock_and_mint!(points_to_lock, EMISSION_THRESHOLD)

        if tx&.persisted?
          created_tx_ids << tx.id
          stats[:minted_count] += tokens_to_mint
        end

      rescue StandardError => e
        stats[:errors] += 1
        Rails.logger.error "🛑 [NAM-ŠID] Помилка вузла Tree #{wallet.tree&.did}: #{e.message}"
        # Продовжуємо обробку лісу, падіння одного дерева не зупиняє всю систему
      end
    end

    # 2. ПАКЕТНА ЕМІСІЯ (Gas Saving Mode)
    # Якщо за результатами аудиту створено транзакції — відправляємо їх одним батчем у Polygon.
    if created_tx_ids.any?
      Rails.logger.info "📦 [NAM-ŠID] Ініціація пакетного мінтингу для #{created_tx_ids.size} транзакцій..."

      # Виклик оновленого сервісу, який використовує функцію batchMint у смарт-контракті.
      # Це запобігає ситуації, коли індивідуальні воркери MintCarbonCoinWorker
      # змагаються за Nonce гаманця Оракула.
      BlockchainMintingService.call_batch(created_tx_ids)
    end

    log_final_stats(stats)
  end

  private

  def log_final_stats(stats)
    Rails.logger.info <<~LOG
      ✅ [NAM-ŠID] Аудит завершено успішно.
      - Проскановано гаманців: #{stats[:wallets_scanned]}
      - Підготовлено до випуску: #{stats[:minted_count]} SCC
      - Сформовано транзакцій: #{stats[:minted_count] > 0 ? (stats[:minted_count] > 0 ? 1 : 0) : 0} (batch)
      - Критичних збоїв: #{stats[:errors]}
    LOG
  end
end
