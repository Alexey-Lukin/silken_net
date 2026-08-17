# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# = ===================================================================
# 🌿 CELO REWARD :pending RECONCILE (ARCH.64 — розрив у ARCH.50 auto-heal)
# = ===================================================================
# ARCH.50 подавав `CommunityRewardService` як "money-path-hardened, auto-heal",
# але Celo-aware reconcile (`CeloConfirmationWorker`) озброюється ЛИШЕ для
# :sent-intent'ів (гілка `if intent.status_sent?`). Reward-intent, що застряг
# у :pending, НЕ озброює жодного reconcile:
#   • transient RPC-timeout → `handle_transact_failure` else-гілка лишає :pending
#     і re-raise → Sidekiq retry бачить :pending у `reward_already_sent?` →
#     dedup-skip, job "успішний" (self-masking — навіть DeadSet мовчить);
#   • `CeloConfirmationWorker` дивиться лише :sent;
#   • `StuckSentTransactionSweeperWorker` + `MintBatchCollectorService` = evm-only.
# Наслідок: transient timeout (норма для RPC) = тиха недоплата cUSD за день,
# без сигналу. Коментарі "reconcile розрулить" описували механізм, якого не було —
# цей воркер його реалізує (дзеркало ARCH.55 :processing-orphan sweep).
#
# [MONEY-SAFE, не blind re-pay]: застряглий :pending НЕ має tx_hash (transact
# кинув до повернення hash) → on-chain-доля виплати AMBIGUOUS: cUSD МІГ піти.
# Тож escalate → :manual_review (людська звірка recipient на Celo explorer),
# НІКОЛИ blind re-pay (dedup через `reward_already_sent?` тримає re-pay до
# ручного рішення). Видимість безкоштовна: `silkennet_blockchain_manual_review_depth`
# (G1, `Treasury::MonitorService`) + `sn-alert-manual-review-depth` (P1) ловлять глибину черги.
class CeloRewardReconcileWorker
  include Sidekiq::Job

  # web3 (recovery, не час-критичний intake). `unique_for` = Enterprise-шим (зараз no-op
  # без sidekiq-ent); overlap безпечний і так — reload-guard + ідемпотентний escalate.
  sidekiq_options queue: "web3", retry: 3, unique_for: 25.minutes

  # :pending старший за це = живий retry-цикл (`CeloRewardWorker` retry:3 + backoff)
  # вже вичерпано, а reconcile так і не озброївся → застряглий труп-intent.
  STALE_THRESHOLD = 30.minutes

  # Нижня межа partition-prune (`created_at` RANGE): reward денний, :pending
  # старший за це давно поза recovery-вікном (окремий forensic-шлях), а cron
  # ловить свіжі труп-intent'и наступним прогоном.
  LOOKBACK = 7.days

  # Стеля re-escalate за прогін — беклог дренажиться послідовними cron'ами,
  # а не одним flood'ом.
  BATCH_LIMIT = 500

  def perform
    cutoff = STALE_THRESHOLD.ago

    stale = BlockchainTransaction.status_pending
                                 .where(token_type: :cusd, blockchain_network: "celo")
                                 .where(created_at: LOOKBACK.ago..cutoff)
                                 .order(:created_at)
                                 .limit(BATCH_LIMIT)
                                 .to_a
    return if stale.empty?

    escalated = 0
    stale.each do |tx|
      # Reload-guard (partition-pruned — голий `.reload` сканував би ВСІ партиції;
      # `created_at` уже в пам'яті з SELECT): живий `CeloConfirmationWorker` / re-run
      # міг довершити intent (`mark_as_sent!` → :sent) між SELECT і цим рядком — stale
      # in-memory :pending не має перетерти свіжий :sent.
      fresh = BlockchainTransaction.find_with_partition_pruning(tx.id, tx.created_at)
      next unless fresh.status_pending?

      fresh.escalate_to_review!(
        "[ARCH.64] Celo reward intent застряг :pending >#{STALE_THRESHOLD.inspect} — " \
        "transact-ack втрачено (tx_hash невідомий, виплата ambiguous); " \
        "звірити recipient на Celo explorer перед будь-яким re-pay."
      )
      escalated += 1
    rescue ActiveRecord::RecordNotFound
      next # intent видалено між SELECT і reload — нічого ескалювати
    end

    # 🔴 [PERF.1] Нуль ескалацій ≠ нічого не сталося. Доти тут стояв
    # `return unless escalated.positive?`, і воркер робився ПОВНІСТЮ німим саме тоді,
    # коли reload-гард пропускав усю вибірку — тобто коли до BATCH_LIMIT інтентів
    # висіли `:pending` понад поріг і всі довершились у мілісекундну щілину. Оператор
    # не бачив ані «є N підозрілих», ані «усі виявились живими». Рівень `info`, а не
    # `warn`: це спостереження про здоровий тракт, не інцидент. (Порожня вибірка
    # мовчить окремим `return` вище — свідчить лише РОЗГЛЯНУТЕ, не кожен тик крона.)
    if escalated.zero?
      Rails.logger.info "🌿 [ARCH.64] Розглянуто #{stale.size} Celo-reward :pending-інтент(ів), " \
                        "ескальовано 0 — усіх довершив живий CeloConfirmationWorker між " \
                        "SELECT'ом і пере-читанням."
      return
    end

    Rails.logger.warn "🌿 [ARCH.64] Ескальовано #{escalated} застряглих Celo-reward :pending → " \
                      ":manual_review (тиха недоплата тепер видима через manual_review_depth)."
  end
end
