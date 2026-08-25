# SPDX-License-Identifier: AGPL-3.0-or-later
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
#
# ⛔ Тут доти стояв другий пункт — «[INS.1] Fan-out страхового оракула». Він переїхав
# у `ClusterHealthCheckWorker` (ARCH.59, 2026-08-25) і сюди НЕ повертається: цей
# колбек у проді не виконується (шим `Sidekiq::Batch`, `sidekiq-pro` поза Gemfile —
# DOC-R.10), тож fan-out тут був єдиним enqueue-сайтом `InsuranceOracleWorker`, до
# якого не доходить керування. Воркер нижче має власний cron-дублер; додавати сюди
# другий сайт означало б завести дім, який мовчить рівно тоді, коли потрібен.
#
# ⛔ Тут доти стояв третій пункт — «Очищує старі TelemetryLog записи (>7 днів)».
# Механізм знято ⚖️ 2026-08-21: рядкове видалення телеметрії заборонене, єдиний
# легітимний ретеншн — дроп партицій ([ARCH.70]). Коментар пережив свій код на
# два дні; носій `spec/quality/telemetry_retention_home_spec.rb` цього не ловить
# за побудовою — він сканує `delete_all`, а не прозу.
class InsightBatchCallbacks
  # Спрацьовує коли ВСІ GenerateClusterInsightWorker джоби успішно завершились.
  # Гарантує, що аудит контрактів запускається тільки після повної агрегації.
  #
  # @param status [Sidekiq::Batch::Status] статус батчу (bid, total, failures)
  # @param options [Hash] параметри, передані при реєстрації колбека
  def on_success(status, options)
    date_string = options["date"]

    Rails.logger.info "✅ [Insight Batch] Батч #{status.bid} завершено успішно. " \
                      "Дата: #{date_string}. Запуск аудиту контрактів..."

    # Аудит NaaS-контрактів (Slashing Protocol / Celo Rewards) + [INS.1] fan-out
    # страхового оракула, який живе ВСЕРЕДИНІ цього воркера (шапка вище).
    ClusterHealthCheckWorker.perform_async(date_string)
  end
end
