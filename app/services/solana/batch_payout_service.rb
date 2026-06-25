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

      # [ARCH.45] In-flight guard — попередня виплата ще не фіналізована: звіряємо on-chain,
      # НЕ платимо наосліп. Закриває crash-window double-pay (краш між broadcast і Kredis →
      # наступний годинний cron бачив незанулений лічильник і платив удруге).
      existing = wallet.blockchain_transactions
                       .where(blockchain_network: "solana").in_flight
                       .order(created_at: :desc).first
      return reconcile_in_flight(service, wallet_id, existing) if existing

      event_count = count_counter(wallet_id).value.to_i
      service.batch_payout!(pending, event_count)
      # [ARCH.45] Kredis НЕ decrement тут — лише після on-chain confirm (reconcile наступного
      # циклу). Тримання pending зайвий цикл безпечне: in-flight guard не дасть повторну виплату.
    end

    # [ARCH.45] Звіряє in-flight виплату й завершує облік детермінованим Kredis-settle.
    def reconcile_in_flight(service, wallet_id, tx)
      case service.signature_status(tx.tx_hash)
      when :confirmed
        tx.mark_as_sent!(tx.tx_hash) if tx.status_pending?
        tx.confirm! unless tx.status_confirmed?
        settle_kredis(wallet_id, tx)
        Rails.logger.info "🌊 [Solana BatchPayout] Wallet ##{wallet_id}: виплату #{tx.tx_hash} підтверджено on-chain — Kredis узгоджено."
      when :not_found
        tx.fail!("Solana batch payout відсутня on-chain — re-pay наступного циклу (ARCH.45)")
        Rails.logger.warn "🌊 [Solana BatchPayout] Wallet ##{wallet_id}: tx #{tx.tx_hash} не дійшла — pending лишається на re-pay."
      else # :processing — ще в мережі, чекаємо наступного циклу
        Rails.logger.info "🌊 [Solana BatchPayout] Wallet ##{wallet_id}: tx #{tx.tx_hash} ще в польоті — пропускаємо цикл."
      end
    end

    # Детермінований decrement саме тих сум, що виплатила ця tx (concurrent надбавки виживають).
    def settle_kredis(wallet_id, tx)
      lamports = (tx.amount.to_d * 1_000_000).to_i
      events   = tx.notes.to_s[/events:(\d+)/, 1].to_i
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
