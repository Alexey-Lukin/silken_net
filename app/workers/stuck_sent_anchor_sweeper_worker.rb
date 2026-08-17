# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# = ===================================================================
# 🧹 STUCK-:sent ANCHOR SWEEPER (ARCH.66 — L1 Confirmation Backstop)
# = ===================================================================
# Primary lifecycle-драйвер — EthereumAnchorConfirmationWorker (enqueue одразу після
# broadcast). Цей cron — backstop для випадку, коли САМ поллер загинув до вичерпання
# ретраїв (container OOM/eviction під час ~3год поллінгу): anchor лишається :sent,
# retries не вичерпані (job зник) → жоден escalate не спрацює, double-anchor guard
# деградує до тижневого таймера (00_07 ARCH.66).
#
# Fix: періодично re-arm EthereumAnchorConfirmationWorker для будь-якого anchor, що
# завис у :sent довше за STUCK_SENT_THRESHOLD (модель, One-Home предикат `stuck_sent`).
# Re-poll РОЗВ'ЯЗУЄ →:confirmed/:failed/:manual_review так само, як оригінальний поллінг
# мав би. НІКОЛИ re-broadcast (лише read-only re-poll): poll достатньо для :sent, а розштовхати
# застряглий tx = операторський same-nonce gas-bump. nonce персиститься перед broadcast
# [ARCH.66 companion] → навіть resume-re-send іде на тому ж слоті, не N+1 — але sweeper НЕ re-send'ить.
#
# [дзеркало ARCH.55 StuckSentTransactionSweeperWorker, L1-специфіка] EthereumAnchor
# непартиційований → plain .reload (не find_with_partition_pruning), perform_async(id)
# (не tx_hash+created_at). Depth-gauge семплить Treasury::MonitorService (15-хв, freshness),
# НЕ цей hourly cron — in-process gauge обнуляється на restart, тож частіший money-path
# прохід дає осмисленіше alert-вікно.
class StuckSentAnchorSweeperWorker
  include Sidekiq::Job

  # web3_low (recovery, не час-критично). unique_for проти overlap двох cron'ів (no-op без
  # Enterprise; безпечно й так — ConfirmationWorker.unique_for + confirm! with_lock роблять
  # дубль-re-arm no-op'ом). 55хв < hourly-cadence → сусідні прогони не перетинаються.
  sidekiq_options queue: "web3_low", retry: 3, unique_for: 55.minutes

  # Стеля re-arm за прогін — беклог дренажиться послідовними cron'ами, не одним flood'ом
  # (anchor-обсяг мізерний — 1/тиждень — але симетрія з рештою reconcile-cron'ів).
  BATCH_LIMIT = 500

  def perform
    stuck = EthereumAnchor.stuck_sent.order(:created_at).limit(BATCH_LIMIT).to_a
    return if stuck.empty?

    re_armed = 0
    stuck.each do |anchor|
      # Reload-guard: живий поллер / re-run міг довершити anchor (→:confirmed/тощо) між
      # SELECT і цим рядком → stale in-memory :sent не має тригерити зайвий re-arm.
      # Непартиційована таблиця → plain .reload.
      next unless anchor.reload.status_sent?

      EthereumAnchorConfirmationWorker.perform_async(anchor.id)
      re_armed += 1
    rescue ActiveRecord::RecordNotFound
      next # anchor видалено між SELECT і reload — нічого re-arm'ити
    end

    # 🔴 [PERF.1] Нуль re-arm'ів ≠ нічого не сталося: без цього ліхтаря свіпер німий
    # саме тоді, коли reload-гард пропустив УСЮ вибірку. Тут ціна вища за обсяг
    # (1 якір/тиждень): мовчання стосується доказової бази L1. `info`, не `warn` —
    # це спостереження про здоровий тракт; порожня вибірка мовчить окремим `return`.
    if re_armed.zero?
      Rails.logger.info "🧹 [ARCH.66] Розглянуто #{stuck.size} stuck-:sent anchor(s), " \
                        "re-armed 0 — усіх довершив живий поллер між SELECT'ом і пере-читанням."
      return
    end

    Rails.logger.warn "🧹 [ARCH.66] Re-armed #{re_armed} stuck-:sent anchor(s) " \
                      "(updated_at older than #{EthereumAnchor::STUCK_SENT_THRESHOLD.inspect}) for confirmation."
  end
end
