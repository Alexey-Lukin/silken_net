# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# = ===================================================================
# 💰 TOKENOMICS BATCH CALLBACKS (Sidekiq Pro Batch Orchestration)
# = ===================================================================
# Колбеки, що спрацьовують після завершення батчу EvaluateTreeBatchWorker.
#
# Sidekiq Pro гарантує:
# - on_success: спрацює ТІЛЬКИ якщо ВСІ джоби батчу виконані успішно
# - on_complete: спрацює коли всі джоби завершились (включаючи failed)
#
# Цей колбек ініціює MintCarbonCoinWorker для пакетного мінтингу
# всіх pending BlockchainTransaction, створених під час циклу.
#
# ⛔ Тут доти стояв `sample_stalled_depth!` — семпл ARCH.94-детектора застряглої
# емісії. Він переїхав у `MintStallProbeWorker` (cron `55 * * * *`) 2026-08-25 і
# сюди НЕ повертається: `on(:success)` означає «всі джоби батчу завершились БЕЗ
# ПОМИЛОК», тож детектор, повішений на нього, мовчить рівно в тому сценарії, який
# має ловити — коли чанки емісії падають. Повна підстава — шапка того воркера.
class TokenomicsBatchCallbacks
  # Спрацьовує коли ВСІ EvaluateTreeBatchWorker джоби успішно завершились.
  # Гарантує, що мінтинг запускається тільки після повної оцінки всього лісу.
  #
  # @param status [Sidekiq::Batch::Status] статус батчу (bid, total, failures)
  # @param options [Hash] параметри, передані при реєстрації колбека
  def on_success(status, options)
    cycle_id = options["cycle_id"]

    Rails.logger.info "✅ [NAM-ŠID] Батч #{status.bid} завершено успішно. " \
                      "Цикл: #{cycle_id}. Ініціація пакетного мінтингу..."

    # [AUTO-DISCOVERY]: MintCarbonCoinWorker без аргументів автоматично знаходить
    # всі pending BlockchainTransaction та виконує пакетний мінтинг.
    # Це елегантніше за передачу масиву TX IDs через Redis/Batch metadata,
    # особливо при масштабі 10M+ дерев де IDs можуть зайняти десятки МБ.
    MintCarbonCoinWorker.perform_async
  end
end
