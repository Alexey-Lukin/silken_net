# frozen_string_literal: true

class BlockchainConfirmationWorker
  include ApplicationWeb3Worker
  # Web3 Critical черга. 10 ретраїв з експоненціальною паузою
  # дають системі близько 15-20 хвилин на очікування підтвердження мережею.
  # [UNIQUE_FOR]: Запобігає конкурентному поллінгу того ж tx_hash.
  # Якщо джоба для цього хешу вже виконується — нова буде відхилена.
  sidekiq_options queue: "web3_critical", retry: 10, unique_for: 10.minutes

  def perform(tx_hash)
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
      txs = BlockchainTransaction.where(tx_hash: tx_hash)

      if txs.empty?
        Rails.logger.warn "⚠️ [Web3] Знайдено квитанцію для невідомого хешу: #{tx_hash}. Ігноруємо."
        return
      end

      if status == "0x1" # Success (Успіх)
        ActiveRecord::Base.transaction do
          txs.each(&:confirm!)
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
