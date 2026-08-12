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

    sample_stalled_depth!

    # [AUTO-DISCOVERY]: MintCarbonCoinWorker без аргументів автоматично знаходить
    # всі pending BlockchainTransaction та виконує пакетний мінтинг.
    # Це елегантніше за передачу масиву TX IDs через Redis/Batch metadata,
    # особливо при масштабі 10M+ дерев де IDs можуть зайняти десятки МБ.
    MintCarbonCoinWorker.perform_async
  end

  private

  # [ARCH.94] Детектор застрягання емісії, і саме ТУТ його єдине чесне місце.
  #
  # Мінт піднімає `locked_balance`, тож `available_balance` падає нижче порога —
  # отже ПІСЛЯ здорового циклу eligible-множина порожня **за побудовою**.
  # Усе, що в ній лишилось, змінтувати мало й не змінтувало.
  #
  # Чому не лічильник помилок: той ловить лише відмови, які КИНУЛИ виняток.
  # Відмова без винятку (порожній селектор, знятий cron, хибний фільтр) лишає
  # лічильник у нулі, а нуль спроб для SLO-відношення невідрізненний від спокою
  # (алерт несе гард `and attempts > 0`). Лічильник СТАНУ бачить обидва режими.
  #
  # Семпл best-effort: детектор видимості не сміє завалити грошовий тракт.
  def sample_stalled_depth!
    SilkenNet::Metrics::MINT_ELIGIBLE_UNMINTED_DEPTH.set(
      TokenomicsEvaluatorWorker.eligible_wallets.count
    )
  rescue StandardError => e
    Rails.logger.warn "⚠️ [ARCH.94] Не вдалось зняти stall-глибину (мінт НЕ зачеплено): #{e.message}"
  end
end
