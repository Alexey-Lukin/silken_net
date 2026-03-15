# frozen_string_literal: true

class TokenomicsEvaluatorWorker
  include Sidekiq::Job

  # [UNIQUE_FOR]: Sidekiq Enterprise Unique Jobs — запобігає перетину
  # щогодинних циклів. Якщо попередній цикл ще виконується,
  # новий буде відхилено замість створення конкурентного батчу.
  sidekiq_options queue: "default", retry: 3, unique_for: 30.minutes

  # [СИНХРОНІЗОВАНО]: 1 SCC (Silken Carbon Coin) = 10,000 балів гомеостазу.
  # Ця константа є фундаментом нашої токеноміки.
  EMISSION_THRESHOLD = 10_000

  # [МАСШТАБ]: Кількість гаманців в одному EvaluateTreeBatchWorker.
  # При 10M дерев = 10,000 чанків, при 1B = 1,000,000 чанків.
  # Оптимальний розмір: достатньо великий для ефективності БД,
  # достатньо малий для паралелізму Sidekiq.
  BATCH_CHUNK_SIZE = 1_000

  # [SIDEKIQ PRO BATCH]: Замість синхронної обробки мільйонів гаманців
  # у одному процесі, створюємо оркестрований батч.
  # Sidekiq Pro відстежує прогрес кожного EvaluateTreeBatchWorker
  # і гарантує виклик TokenomicsBatchCallbacks#on_success тільки
  # після завершення ВСІХ чанків.
  def perform
    cycle_id = SecureRandom.uuid
    Rails.logger.info "⚖️ [NAM-ŠID] Початок циклу емісії #{cycle_id}..."

    batch = Sidekiq::Batch.new
    batch.description = "Tokenomics Cycle #{cycle_id}"
    batch.on(:success, TokenomicsBatchCallbacks, "cycle_id" => cycle_id)

    chunks_enqueued = 0

    batch.jobs do
      eligible_wallets.in_batches(of: BATCH_CHUNK_SIZE) do |relation|
        EvaluateTreeBatchWorker.perform_async(relation.pluck(:id), cycle_id)
        chunks_enqueued += 1
      end
    end

    Rails.logger.info "📦 [NAM-ŠID] Батч #{batch.bid}: #{chunks_enqueued} чанків " \
                      "по #{BATCH_CHUNK_SIZE} гаманців. Очікуємо завершення..."
  end

  private

  # Scope для eligible гаманців: активні дерева з балансом >= порогу емісії.
  def eligible_wallets
    Wallet.joins(:tree)
          .where(trees: { status: :active })
          .where("balance >= ?", EMISSION_THRESHOLD)
  end
end
