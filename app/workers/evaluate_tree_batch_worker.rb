# SPDX-License-Identifier: AGPL-3.0-or-later
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
        # [ARCH.94] Сайзинг мусить читати ТУ САМУ величину, що й гард
        # `lock_and_mint!` — тобто НЕсконвертований залишок. `balance` тут gross:
        # сконвертовані бали лишаються в `locked_balance` назавжди (04_01 §6 E.66),
        # тож сайзинг від нього просить більше, ніж доступно, з другого ж циклу.
        tokens_to_mint = (wallet.available_balance / threshold).to_i
        next if tokens_to_mint.zero?

        points_to_lock = tokens_to_mint * threshold
        tx = wallet.lock_and_mint!(points_to_lock, threshold)

        # [DOC-T.89] Лічимо ЛЕДЖЕР (`tx.amount`), а не власний намір (`tokens_to_mint`).
        # Обидві величини сьогодні тотожні, і тримають це три незалежні примуси:
        # integer-typed `emission_threshold` (гейт GOV.3), добуток < 2⁵³, і CHECK
        # `wallets_balance_invariants` на невідʼємність. Але конверсію рахують ДВІ
        # арифметики — тут BigDecimal, у `lock_and_mint!` Float, — і якщо вони колись
        # розійдуться, намір збреше НА КОРИСТЬ воркера: метрика й лог покажуть, скільки
        # ми хотіли, а не скільки лягло в леджер. Той самий клас, що [ARCH.94], де
        # виняток жив лише в лічильнику й джоба поверталась успіхом.
        stats[:minted] += tx.amount.to_i if tx&.persisted?
      rescue StandardError => e
        stats[:errors] += 1
        # [ARCH.94] Доти цей виняток жив лише в лічильнику й лог-рядку: джоба
        # поверталась успіхом, retry не було, DeadSet лишався порожній, а
        # mint-метрики не рухались узагалі (tx не створено → гаманець не входив
        # навіть у ЗНАМЕННИК SLO). Саме так P1 і прожив непоміченим.
        SilkenNet::Metrics::MINT_CHUNK_ERRORS_TOTAL.increment
        Rails.logger.error "🛑 [NAM-ŠID] Помилка вузла Tree #{wallet.tree&.did}: #{e.message}"
        # Продовжуємо обробку — падіння одного дерева не зупиняє весь чанк
      end
    end

    Rails.logger.info "📊 [NAM-ŠID] Чанк #{cycle_id}: оброблено #{stats[:processed]}, " \
                      "емісія #{stats[:minted]} SCC, помилок #{stats[:errors]}"
  end
end
