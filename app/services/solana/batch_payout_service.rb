# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Solana
  # =========================================================================
  # 🌊 SOLANA BATCH PAYOUT SERVICE (Gas Optimizer) [E.61]
  # =========================================================================
  # Виплачує акумульовані мікро-винагороди одним TransferChecked на гаманець,
  # коли сума перетне поріг. Працює у парі з Solana::MintingService, який у
  # batch-режимі (поріг > 0) лише акумулює винагороди в Kredis замість окремих
  # per-event транзакцій — газ на дрібну виплату зрівнюється з самою винагородою.
  #
  # Обґрунтування (Scale) + поріг — канон 05_01 §8.
  #
  # Використання: Solana::BatchPayoutService.call
  # =========================================================================
  class BatchPayoutService < ApplicationService
    # Вікно per-wallet локу — покриває один RPC-round-trip виплати.
    PAYOUT_LOCK_TIMEOUT = 60.seconds

    def perform
      threshold = batch_threshold_lamports
      return if threshold.zero? # batch вимкнено (поріг 0 → per-event) → нічого робити

      wallet_ids = pending_wallets.members
      return if wallet_ids.empty?

      wallet_ids.each { |wallet_id| flush_wallet(wallet_id.to_i, threshold) }
    end

    private

    # Виплачує накопичене для одного гаманця, якщо воно перетнуло поріг.
    # Per-wallet rescue: збій одного гаманця не зриває решту батчу.
    def flush_wallet(wallet_id, threshold)
      # Дешева перевірка без локу — більшість гаманців ще не дозріли.
      return if pending_counter(wallet_id).value.to_i < threshold

      Kredis.lock(lock_key(wallet_id), expires_in: PAYOUT_LOCK_TIMEOUT, after_timeout: :raise) do
        pending = pending_counter(wallet_id).value.to_i
        next if pending < threshold # double-check під локом (інший процес міг виплатити)

        wallet = Wallet.find_by(id: wallet_id)
        if wallet.nil?
          discard_orphan(wallet_id)
        else
          pay_wallet(wallet, wallet_id, pending)
        end
      end
    rescue StandardError => e
      Rails.logger.error "🛑 [Solana BatchPayout] Wallet ##{wallet_id} failed: #{e.message}"
    end

    def pay_wallet(wallet, wallet_id, pending)
      service = Solana::MintingService.new(nil, wallet: wallet)

      # [ARCH.45] Будь-яка незавершена Solana-виплата звіряється on-chain, НЕ платимо наосліп.
      # 7-денне вікно `unsettled_within` (модель) дає ~168 reconcile-шансів
      # ⚠️ Прунінгу воно НЕ дає: `OR` у скоупі знімає партиційний відбір цілком (виміряно
      # EXPLAIN'ом — усі 9 листів). Вартість тримає індекс `wallet_id`, не партиція.
      # (вузьке 2h дало б лише один → window-expiry double-pay). `:manual_review` теж блокує re-pay
      # (можливо-landed виплата під ручною звіркою).
      unsettled = wallet.blockchain_transactions
                        .where(blockchain_network: "solana")
                        .unsettled_within(7.days)
                        .order(created_at: :desc).first
      return reconcile_in_flight(service, wallet_id, unsettled) if unsettled

      event_count = count_counter(wallet_id).value.to_i
      SilkenNet::Metrics::SOLANA_PAYOUT_ATTEMPTS_TOTAL.increment
      service.batch_payout!(pending, event_count)
      SilkenNet::Metrics::SOLANA_PAYOUT_SUCCESS_TOTAL.increment
      # [ARCH.45] Kredis НЕ decrement тут — лише після on-chain confirm (reconcile наступного
      # циклу). Тримання pending зайвий цикл безпечне: in-flight guard не дасть повторну виплату.
    end

    # [ARCH.45] Звіряє незавершену виплату on-chain і завершує облік (НЕ платить наосліп).
    def reconcile_in_flight(service, wallet_id, tx)
      case service.signature_status(tx.tx_hash)
      when :confirmed
        # Виплата landed → settle Kredis (блокує re-pay) + перевести у :confirmed, де дозволено.
        # [INF.26] Дискримінатор ПЕРЕД переходом: `:pending` тут означає, що процес упав
        # усередині `batch_payout!` (до `mark_as_sent!`), тобто інкремент щасливого шляху
        # НЕ стався — лише тоді ця гілка є чисельником. Доти вона інкрементила БЕЗУМОВНО,
        # а `:sent` входить в `unsettled_within`, тож кожна нормальна виплата лічилась
        # двічі (broadcast + confirm наступного циклу) при знаменнику +0 — панель
        # `success/attempts` читала б ~200 % замість SLO.
        crash_recovered = tx.status_pending?

        # 🔴 [ARCH.115] Той самий гард, що в per-event сиблінгу: `may_confirm?` доти САМ
        # відсікав `:manual_review`, бо подія його не приймала. Операторський вихід це
        # змінив, тож ambiguous-рядок відсікаємо ЯВНО — інакше машина закриває те, що
        # ескальовано саме через невідомість долі.
        tx.mark_as_sent!(tx.tx_hash) if tx.status_pending?
        tx.confirm! if tx.may_confirm? && !tx.status_manual_review?
        settle_kredis(wallet_id, tx)
        # Чисельник визначений як BROADCAST (докстрінг + три сиблінги SLO), тож рахуємо
        # лише випадок, де broadcast стався, а лічильник його проґавив через крах.
        SilkenNet::Metrics::SOLANA_PAYOUT_SUCCESS_TOTAL.increment if crash_recovered
        Rails.logger.info "🌊 [Solana BatchPayout] Wallet ##{wallet_id}: виплату #{tx.tx_hash} підтверджено on-chain — Kredis узгоджено."
      when :not_found
        # getSignatureStatuses :not_found НЕ авторитетне (RPC-лаг / history
        # retention) — сліпий re-pay = double-pay, якщо tx насправді landed. Ескалюємо в
        # manual_review (double-spend guard), НЕ авто-re-pay; наступні цикли re-звіряють
        # (auto-heal якщо нода наздожене), інакше людина закриває.
        tx.escalate_to_review!("Solana payout не знайдено on-chain — ручна звірка перед re-pay (можливий RPC-лаг; ARCH.45)") if tx.may_escalate_to_review?
        Rails.logger.warn "🌊 [Solana BatchPayout] Wallet ##{wallet_id}: tx #{tx.tx_hash} не знайдено on-chain → manual_review (без авто-re-pay)."
      else # :processing — ще в мережі, чекаємо наступного циклу
        Rails.logger.info "🌊 [Solana BatchPayout] Wallet ##{wallet_id}: tx #{tx.tx_hash} ще в польоті — пропускаємо цикл."
      end
    end

    # Детермінований decrement саме тих сум, що виплатила ця tx (concurrent надбавки виживають).
    def settle_kredis(wallet_id, tx)
      lamports = (tx.amount.to_d * 1_000_000).to_i
      events   = tx.notes.to_s[/events:(\d+)/, 1].to_i
      # lamports = amount×1e6; реальний payout = N лампортів / 1e6 (amount>0 validation) ⇒
      # lamports ≥ 1 завжди; else (0) dead — dust-захист (§B.4 leave).
      pending_counter(wallet_id).decrement(by: lamports) if lamports.positive?
      count_counter(wallet_id).decrement(by: events) if events.positive?
      drain_set_if_empty(wallet_id)
    end

    # Гаманець зник із БД → скидаємо «висячий» Kredis-залишок, щоб cron його не возив.
    def discard_orphan(wallet_id)
      pending_counter(wallet_id).reset
      count_counter(wallet_id).reset
      pending_wallets.remove(wallet_id.to_s)
      Rails.logger.warn "⚠️ [Solana BatchPayout] Wallet ##{wallet_id} відсутній — pending залишок скинуто"
    end

    def drain_set_if_empty(wallet_id)
      return if pending_counter(wallet_id).value.to_i.positive? # лишився concurrent залишок

      pending_wallets.remove(wallet_id.to_s)
    end

    # Дзеркало Solana::MintingService#batch_threshold_lamports (governance-aware).
    def batch_threshold_lamports
      usdc = SystemParameter.current(:solana_batch_threshold_usdc, default: 0).to_f
      (usdc * 1_000_000).to_i
    end

    def pending_wallets
      Kredis.set(Solana::MintingService::PENDING_PAYOUT_WALLETS_KEY)
    end

    def pending_counter(wallet_id)
      Kredis.counter("solana_pending_payouts:#{wallet_id}")
    end

    def count_counter(wallet_id)
      Kredis.counter("solana_pending_payout_count:#{wallet_id}")
    end

    def lock_key(wallet_id)
      "solana_payout_lock:#{wallet_id}"
    end
  end
end
