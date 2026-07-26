# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class BlockchainConfirmationWorker
  include ApplicationWeb3Worker
  # Web3 Critical черга. 10 ретраїв з експоненціальною паузою
  # дають системі близько 15-20 хвилин на очікування підтвердження мережею.
  # [UNIQUE_FOR]: Запобігає конкурентному поллінгу того ж tx_hash.
  # Якщо джоба для цього хешу вже виконується — нова буде відхилена.
  sidekiq_options queue: "web3_critical", retry: 10, unique_for: 10.minutes

  # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
  # 🛡️ MEMPOOL LIMBO GUARD (The Stuck Transaction Safety Net)
  # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
  # Викликається, коли всі 10 ретраїв вичерпано (~15-20 хвилин polling),
  # а транзакція так і не отримала receipt від мережі.
  # Без цього хендлера job потрапляє в Sidekiq Dead queue і транзакції
  # назавжди залишаються в статусі :sent — кошти зависають у locked_balance.
  #
  # Делегуємо до MintingRollbackService, який:
  #   - Перевіряє receipt ще раз (можливо, мережа відновилась)
  #   - Підтверджує on-chain якщо receipt з'явився
  #   - Ескалює до manual_review якщо receipt все ще pending/unknown
  # [ARCH.52] tx_hash-query + created_at LOWER-bound → partition-prune (RANGE по created_at).
  # batchMint групує pending tx БЕЗ верхньої age-межі (urgent-batch span необмежений — reset-to-
  # pending тримає старий created_at) одним tx_hash → рядки мають РІЗНІ created_at у [earliest,
  # broadcast]. `created_at >= earliest-1h` покриває ВСІ рядки батчу (всі ≥ earliest) і прунить
  # партиції, старші за earliest-1h. ⚠️ Симетричне ±1h ВИКЛЮЧИЛО б рядки >1h новіші за earliest →
  # stuck :sent. Дзеркало CeloConfirmationWorker/ARCH.50 (по tx_hash, не id — batch ділить хеш;
  # lower-bound, не 1-sec — batch span). Fallback (created_at_iso=nil) → unscoped (legacy/puro).
  def self.confirmation_scope(tx_hash, created_at_iso = nil)
    scope = BlockchainTransaction.where(tx_hash: tx_hash)
    return scope if created_at_iso.blank?

    t = Time.iso8601(created_at_iso.to_s)
    scope.where("created_at >= ?", t - 1.hour)
  rescue ArgumentError, TypeError
    BlockchainTransaction.where(tx_hash: tx_hash)
  end

  sidekiq_retries_exhausted do |msg, _ex|
    tx_hash, created_at_iso = msg["args"]
    next unless tx_hash

    Rails.logger.error "🚨 [Web3] Confirmation polling exhausted for TX: #{tx_hash}. " \
                       "Escalating stuck transactions to MintingRollbackService."

    txs = confirmation_scope(tx_hash, created_at_iso).where(status: :sent)
    if txs.any?
      MintingRollbackService.call(transactions: txs)
    else
      Rails.logger.warn "⚠️ [Web3] No :sent transactions found for exhausted TX: #{tx_hash}. " \
                        "Possibly already resolved by another process."
    end
  end

  def perform(tx_hash, created_at_iso = nil)
    # [RATE LIMITED]: RPC виклик захищений глобальним лімітером.
    # Тільки eth_get_transaction_receipt є RPC-операцією;
    # обробка результату — це DB-операції, що не потребують лімітування.
    receipt = within_rpc_limit do
      # 1. ПІДКЛЮЧЕННЯ ДО МАТРИЦІ (Thread-cached RPC client)
      client = Web3::RpcConnectionPool.client_for("ALCHEMY_POLYGON_RPC_URL")

      # Запитуємо квитанцію (receipt) транзакції
      # У 2026 році Alchemy повертає результат миттєво, якщо блок вже сформовано.
      client.eth_get_transaction_receipt(tx_hash)
    end

    # 2. АНАЛІЗ РЕАЛЬНОСТІ
    if receipt && receipt["result"]
      status = receipt["result"]["status"]

      # Знаходимо всі транзакції (батч або одну), пов'язані з цим хешем
      # [ARCH.52] partition-pruned по created_at вікну (fallback unscoped якщо created_at_iso=nil).
      txs = self.class.confirmation_scope(tx_hash, created_at_iso)

      if txs.empty?
        Rails.logger.warn "⚠️ [Web3] Знайдено квитанцію для невідомого хешу: #{tx_hash}. Ігноруємо."
        return
      end

      if status == "0x1" # Success (Успіх)
        block_num = receipt["result"]["blockNumber"]&.then { |v| v.to_i(16) }
        gas_used  = receipt["result"]["gasUsed"]&.then { |v| v.to_i(16) }
        ActiveRecord::Base.transaction do
          txs.each { |tx| tx.confirm!(block_num, gas_used) }
        end
        Rails.logger.info "💎 [Web3] Блокчейн підтвердив емісію: #{tx_hash}. Капітал легалізовано."
      else # Reverted (Провал на рівні смарт-контракту)
        reason = "EVM Revert: Транзакція відхилена мережею (можливо, Gas Limit або логіка контракту)."
        txs.each { |tx| tx.fail!(reason) }

        # [КРИТИЧНО]: Якщо батч впав, це потребує негайного аудиту
        Rails.logger.error "🚨 [Web3 Critical] Провал транзакції в Polygon: #{tx_hash}"
      end
    else
      # 3. ЧАСОВИЙ ПАРАДОКС (Polling)
      # Якщо квитанції ще немає — транзакція все ще в мемпулі.
      # Ми викликаємо помилку, щоб Sidekiq зробив ретрай згідно з налаштуваннями.
      raise "⏳ Очікування підтвердження для #{tx_hash}... (Транзакція ще в мемпулі)"
    end
  end
end
