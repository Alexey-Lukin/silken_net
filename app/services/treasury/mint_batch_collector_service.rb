# frozen_string_literal: true

module Treasury
  # =========================================================================
  # 📦 MINT BATCH COLLECTOR SERVICE (Sidekiq-Level Transaction Aggregation)
  # =========================================================================
  # Збирає pending BlockchainTransaction записи і групує їх у пакети
  # для оптимального batchMint виклику на Polygon.
  #
  # Замість відправки одиночних mint() транзакцій через MintCarbonCoinWorker,
  # цей сервіс періодично збирає пакети pending транзакцій і делегує їх
  # BlockchainMintingService.call_batch — де batchMint() на Solidity рівні
  # обробляє до 200 txs за один виклик.
  #
  # Gas savings: batchMint(100) ≈ 30-40% дешевше ніж 100 × mint()
  #
  # Використання:
  #   Treasury::MintBatchCollectorService.call
  # =========================================================================
  class MintBatchCollectorService < ApplicationService
    # Максимальний розмір пакета для batchMint (обмеження Solidity контракту)
    MAX_BATCH_SIZE = 100

    # Оптимальний розмір пакета для газ-ефективності
    # При 50-100 транзакціях gas overhead мінімальний
    OPTIMAL_BATCH_SIZE = 100

    # Максимальна кількість транзакцій для обробки за один виклик
    MAX_TRANSACTIONS_PER_RUN = 1000

    # Мінімальна кількість транзакцій для формування батча
    # (нижче цього порогу — чекаємо накопичення)
    MIN_BATCH_SIZE = 5

    # Максимальний вік pending транзакції (хвилини) — навіть якщо пакет малий,
    # транзакції старше цього порогу відправляються негайно
    MAX_PENDING_AGE_MINUTES = 30

    def perform
      pending_transactions = fetch_pending_transactions
      return if pending_transactions.empty?

      # Групуємо за типом токена (SCC/SFC мають різні контракти)
      grouped = pending_transactions.group_by(&:token_type)

      grouped.each do |token_type, txs|
        process_token_type_batch(token_type, txs)
      end
    end

    private

    # Знаходить pending транзакції, готові до відправки
    def fetch_pending_transactions
      BlockchainTransaction
        .where(status: :pending, blockchain_network: "evm")
        .where.not(to_address: nil)
        .includes(wallet: :tree)
        .order(created_at: :asc)
        .limit(MAX_TRANSACTIONS_PER_RUN)
    end

    # Обробляє пакет транзакцій одного типу токена
    def process_token_type_batch(token_type, transactions)
      # Розділяємо на urgent (старі) та standard (нові)
      urgent, standard = partition_by_age(transactions)

      # Urgent транзакції відправляються незалежно від розміру батча
      if urgent.any?
        batch_and_dispatch(urgent, token_type, reason: "age threshold exceeded")
      end

      # Standard транзакції збираються у оптимальні пакети
      if standard.size >= MIN_BATCH_SIZE
        batch_and_dispatch(standard, token_type, reason: "batch size threshold")
      elsif standard.any?
        Rails.logger.info "📦 [BatchCollector] #{token_type}: #{standard.size} pending " \
                          "(below #{MIN_BATCH_SIZE} threshold, waiting for accumulation)"
      end
    end

    # Розділяє транзакції на urgent (старіші за MAX_PENDING_AGE_MINUTES) та standard
    def partition_by_age(transactions)
      cutoff = MAX_PENDING_AGE_MINUTES.minutes.ago
      transactions.partition { |tx| tx.created_at < cutoff }
    end

    # Розбиває масив транзакцій на пакети оптимального розміру і відправляє.
    # Делегує напряму до BlockchainMintingService.call_batch — використовує
    # той самий batchMint() flow, що й MintCarbonCoinWorker.
    def batch_and_dispatch(transactions, token_type, reason:)
      transactions.each_slice(OPTIMAL_BATCH_SIZE) do |batch|
        ids = batch.map(&:id)

        Rails.logger.info "📦 [BatchCollector] Dispatching #{ids.size} #{token_type} " \
                          "transactions (#{reason})"

        BlockchainMintingService.call_batch(ids)
      end
    end
  end
end
