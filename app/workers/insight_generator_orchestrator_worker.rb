# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# = ===================================================================
# 🧠 INSIGHT GENERATOR ORCHESTRATOR (Sidekiq Pro Batch)
# = ===================================================================
# [A-3: Wiki 04_02 §11 — Sidekiq Batch для покластерної обробки]
#
# При 10M+ дерев монолітний InsightGeneratorService#perform є OOM-ризиком.
# Аналогічно до TokenomicsEvaluatorWorker (Sidekiq::Batch → EvaluateTreeBatchWorker),
# цей оркестратор розбиває обробку на GenerateClusterInsightWorker чанки.
#
# Sidekiq Pro відстежує прогрес кожного воркера та гарантує виклик
# InsightBatchCallbacks#on_success тільки після завершення ВСІХ чанків.
#
# Використання (з DailyAggregationWorker):
#   InsightGeneratorOrchestratorWorker.perform_async(target_date.to_s)
class InsightGeneratorOrchestratorWorker
  include Sidekiq::Job

  # [UNIQUE_FOR]: Запобігає перетину щоденних циклів.
  # Якщо попередній цикл ще виконується, новий буде відхилено.
  sidekiq_options queue: "low", retry: 3, unique_for: 24.hours

  # [МАСШТАБ]: Кількість кластерів в одному GenerateClusterInsightWorker.
  # При 100K кластерів = 1000 чанків. Оптимальний розмір: достатньо великий
  # для ефективності БД, достатньо малий для паралелізму Sidekiq.
  CLUSTER_BATCH_SIZE = 100

  def perform(date_string = nil)
    target_date = date_string.present? ? Date.parse(date_string) : (Time.current.utc.to_date - 1)

    Rails.logger.info "🧠 [Insight Orchestrator] Початок батч-агрегації за #{target_date}..."

    # 1. Визначаємо кластери з даними (один легкий SQL-запит)
    service = InsightGeneratorService.new(target_date)
    baselines = service.cluster_baselines
    cluster_ids = baselines.keys

    if cluster_ids.empty?
      Rails.logger.warn "⚠️ [Insight Orchestrator] За #{target_date} немає кластерів з даними."
      return
    end

    # 2. Ідемпотентність забезпечується на рівні кожного GenerateClusterInsightWorker:
    # кожен child-воркер видаляє старі інсайти ТІЛЬКИ для своїх кластерів перед створенням нових.
    # Глобальний delete_all тут НЕ потрібен і створює race condition:
    # паралельні воркери можуть вставити інсайти після глобального delete, а інший воркер
    # знову зробить per-cluster delete, видаливши вже створені дані.

    # 3. Створюємо Sidekiq::Batch для оркестрації
    batch = Sidekiq::Batch.new
    batch.description = "Insight Generation #{target_date}"
    batch.on(:success, InsightBatchCallbacks, "date" => target_date.to_s)

    chunks_enqueued = 0

    batch.jobs do
      cluster_ids.each_slice(CLUSTER_BATCH_SIZE) do |chunk|
        GenerateClusterInsightWorker.perform_async(chunk, target_date.to_s)
        chunks_enqueued += 1
      end
    end

    Rails.logger.info "📦 [Insight Orchestrator] Батч #{batch.bid}: #{chunks_enqueued} чанків " \
                      "по #{CLUSTER_BATCH_SIZE} кластерів (#{cluster_ids.size} всього). Очікуємо завершення..."
  end
end
