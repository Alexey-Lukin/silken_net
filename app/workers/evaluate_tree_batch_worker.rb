# frozen_string_literal: true

# = ===================================================================
# 🌳 EVALUATE TREE BATCH WORKER (Sidekiq Pro Batch Child)
# = ===================================================================
# Обробляє чанк гаманців у межах батчу TokenomicsEvaluatorWorker.
# Кожен інстанс отримує масив wallet_ids (до BATCH_CHUNK_SIZE елементів)
# та виконує атомарне lock_and_mint! для кожного eligible гаманця.
#
# [МАСШТАБ]: При 10M–1B дерев, один батч може містити тисячі таких воркерів.
# Sidekiq Pro відстежує прогрес кожного та гарантує виклик колбека
# TokenomicsBatchCallbacks#on_success тільки після завершення ВСІХ чанків.
class EvaluateTreeBatchWorker
  include Sidekiq::Job
  # Та сама черга, що й TokenomicsEvaluatorWorker — фінансовий аудит.
  sidekiq_options queue: "default", retry: 3

  # @param wallet_ids [Array<Integer>] масив ID гаманців для обробки
  # @param cycle_id [String] UUID циклу токеноміки (для аудиту та логування)
  def perform(wallet_ids, cycle_id)
    stats = { processed: 0, minted: 0, errors: 0 }
    # [GOV.1] Один поріг на весь чанк (One-Home: TokenomicsEvaluatorWorker.emission_threshold,
    # DAO-live) — mid-batch governance-зміна не розщеплює чанк на два курси конверсії.
    threshold = TokenomicsEvaluatorWorker.emission_threshold

    Wallet.where(id: wallet_ids).find_each do |wallet|
      stats[:processed] += 1

      begin
        tokens_to_mint = (wallet.balance / threshold).to_i
        next if tokens_to_mint.zero?

        points_to_lock = tokens_to_mint * threshold
        tx = wallet.lock_and_mint!(points_to_lock, threshold)

        stats[:minted] += tokens_to_mint if tx&.persisted?
      rescue StandardError => e
        stats[:errors] += 1
        Rails.logger.error "🛑 [NAM-ŠID] Помилка вузла Tree #{wallet.tree&.did}: #{e.message}"
        # Продовжуємо обробку — падіння одного дерева не зупиняє весь чанк
      end
    end

    Rails.logger.info "📊 [NAM-ŠID] Чанк #{cycle_id}: оброблено #{stats[:processed]}, " \
                      "емісія #{stats[:minted]} SCC, помилок #{stats[:errors]}"
  end
end
