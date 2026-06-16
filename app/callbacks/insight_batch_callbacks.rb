# frozen_string_literal: true

# = ===================================================================
# 🧠 INSIGHT BATCH CALLBACKS (Sidekiq Pro Batch Orchestration)
# = ===================================================================
# [A-3: Wiki 04_02 §11 — Sidekiq Batch для покластерної обробки]
#
# Колбеки, що спрацьовують після завершення батчу GenerateClusterInsightWorker.
#
# Sidekiq Pro гарантує:
# - on_success: спрацює ТІЛЬКИ якщо ВСІ джоби батчу виконані успішно
# - on_complete: спрацює коли всі джоби завершились (включаючи failed)
#
# Цей колбек:
# 1. Запускає ClusterHealthCheckWorker для аудиту NaaS-контрактів
# 2. Очищує старі TelemetryLog записи (>7 днів)
class InsightBatchCallbacks
  # Спрацьовує коли ВСІ GenerateClusterInsightWorker джоби успішно завершились.
  # Гарантує, що аудит контрактів запускається тільки після повної агрегації.
  #
  # @param status [Sidekiq::Batch::Status] статус батчу (bid, total, failures)
  # @param options [Hash] параметри, передані при реєстрації колбека
  def on_success(status, options)
    date_string = options["date"]

    Rails.logger.info "✅ [Insight Batch] Батч #{status.bid} завершено успішно. " \
                      "Дата: #{date_string}. Запуск аудиту контрактів та очищення логів..."

    # 1. Аудит NaaS-контрактів (Slashing Protocol / Celo Rewards)
    ClusterHealthCheckWorker.perform_async(date_string)

    # 2. КЕНОЗИС: Очищення сирих логів старше 7 днів
    # Ідемпотентна операція на іншому діапазоні дат.
    InsightGeneratorService.cleanup_old_logs!
  end
end
