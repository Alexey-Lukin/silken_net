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
      event_count = count_counter(wallet_id).value.to_i

      Solana::MintingService.new(nil, wallet: wallet).batch_payout!(pending, event_count)

      # decrement (НЕ clear) — concurrent incrby з нової події між read і тут не загубиться.
      pending_counter(wallet_id).decrement(by: pending)
      count_counter(wallet_id).decrement(by: event_count)
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
