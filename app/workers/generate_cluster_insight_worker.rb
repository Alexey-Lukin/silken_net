# frozen_string_literal: true

# = ===================================================================
# 🌳 GENERATE CLUSTER INSIGHT WORKER (Sidekiq Pro Batch Child)
# = ===================================================================
# [A-3: Wiki 04_02 §14 — Sidekiq Batch для покластерної обробки]
#
# Обробляє чанк кластерів у межах батчу InsightGeneratorOrchestratorWorker.
# Кожен інстанс отримує масив cluster_ids (до CLUSTER_BATCH_SIZE елементів)
# та створює tree-level і cluster-level AiInsight для кожного кластера.
#
# [МАСШТАБ]: При 10M–1B дерев, один батч може містити тисячі таких воркерів.
# Sidekiq Pro відстежує прогрес кожного та гарантує виклик колбека
# InsightBatchCallbacks#on_success тільки після завершення ВСІХ чанків.
class GenerateClusterInsightWorker
  include Sidekiq::Job

  # Та сама черга, що й InsightGeneratorOrchestratorWorker.
  sidekiq_options queue: "low", retry: 3

  # @param cluster_ids [Array<Integer>] масив ID кластерів для обробки
  # @param date_string [String] ISO8601 дата для агрегації
  def perform(cluster_ids, date_string)
    date = Date.parse(date_string)
    stats = { processed: 0, clusters: 0, errors: 0 }

    service = InsightGeneratorService.new(date)
    processed = service.process_cluster_batch(cluster_ids)

    stats[:processed] = processed
    stats[:clusters] = cluster_ids.size

    Rails.logger.info "📊 [Insight Batch] Чанк #{date}: оброблено #{stats[:processed]} вузлів " \
                      "у #{stats[:clusters]} кластерах."
  rescue StandardError => e
    Rails.logger.error "🛑 [Insight Batch] Помилка чанку #{date}: #{e.message}"
    raise e
  end
end
