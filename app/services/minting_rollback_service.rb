# frozen_string_literal: true

# = ===================================================================
# 🔄 MINTING ROLLBACK SERVICE (The Absolute Integrity)
# = ===================================================================
# Відповідає за повернення заблокованих коштів після вичерпання всіх
# Sidekiq-ретраїв у MintCarbonCoinWorker. Запобігає "зависанню" капіталу
# у locked_balance, коли RPC Polygon перманентно недоступний.
#
# [DOUBLE-SPEND GUARD]: Якщо tx_hash вже існує (транзакція була відправлена
# в мемпул), НЕ розблоковуємо кошти автоматично — ескалюємо до manual_review.
# Це запобігає класичному Double-Spend: блокчейн може змінтити токени навіть
# якщо RPC відвалився до отримання підтвердження.
#
# Логіка:
#   1. tx_hash відсутній → безпечний rollback (транзакція не покинула бекенд)
#   2. tx_hash існує → спробувати getTransactionReceipt через RPC
#      a) receipt є (confirmed) → НЕ робити rollback, підтвердити транзакцію
#      b) receipt null (pending) → manual_review, кошти залишаються заблокованими
#      c) RPC timeout → manual_review, кошти залишаються заблокованими
#
# Використання:
#   MintingRollbackService.call(telemetry_log_id: 123, created_at_iso: "2026-01-01T00:00:00Z")
#   MintingRollbackService.call(transactions: txs)
class MintingRollbackService < ApplicationService
  def initialize(telemetry_log_id: nil, created_at_iso: nil, transactions: nil)
    @telemetry_log_id = telemetry_log_id
    @created_at_iso = created_at_iso
    @transactions = transactions
  end

  def perform
    txs = resolve_transactions
    return if txs.blank?

    txs.each { |tx| rollback_transaction!(tx) }
  end

  private

  def resolve_transactions
    return @transactions if @transactions.present?
    return unless @telemetry_log_id

    log = find_telemetry_log
    return unless log

    wallet = log.tree&.wallet
    return unless wallet

    wallet.blockchain_transactions.where(status: [ :pending, :processing, :sent ])
  end

  def find_telemetry_log
    scope = TelemetryLog.where(id: @telemetry_log_id)
    if @created_at_iso.present?
      begin
        scope = scope.where(created_at: Time.iso8601(@created_at_iso))
      rescue ArgumentError
        # Некоректний формат — шукаємо без partition pruning
        # [S6.16]: degraded path — записуємо counter для observability
        SilkenNet::Metrics::TELEMETRY_LOG_UNPRUNED_LOOKUPS_TOTAL
          .increment(labels: { caller: "MintingRollbackService:invalid_iso8601" })
      end
    else
      # [S6.16]: rollback викликається без created_at_iso (legacy шлях, admin tool) —
      # acceptable у cold path, але трекаємо для прозорості.
      SilkenNet::Metrics::TELEMETRY_LOG_UNPRUNED_LOOKUPS_TOTAL
        .increment(labels: { caller: "MintingRollbackService:missing_created_at_iso" })
    end
    scope.first
  end

  def rollback_transaction!(tx)
    # [GUARD]: Пропускаємо транзакції, що вже у термінальному стані
    return if tx.status.in?(%w[confirmed failed manual_review])

    # [DOUBLE-SPEND GUARD]: Якщо tx_hash існує, транзакція могла потрапити в мемпул.
    # Автоматичний rollback неприпустимий — перевіряємо стан на блокчейні.
    if tx.tx_hash.present?
      handle_transaction_with_hash(tx)
    else
      perform_safe_rollback(tx)
    end
  end

  # Транзакція з tx_hash — потенційно в мемпулі або вже підтверджена.
  # Спробуємо перевірити стан через RPC перед будь-яким рішенням.
  def handle_transaction_with_hash(tx)
    receipt = fetch_transaction_receipt(tx)

    case receipt
    when :confirmed
      # Транзакція успішно підтверджена на блокчейні — НЕ робимо rollback
      Rails.logger.info "✅ [Web3] Транзакція ##{tx.id} (#{tx.tx_hash}) підтверджена on-chain. Rollback скасовано."
      tx.confirm!
    when :reverted
      # Транзакція відхилена EVM — безпечно робити rollback
      Rails.logger.warn "↩️ [Web3] Транзакція ##{tx.id} (#{tx.tx_hash}) reverted on-chain. Виконуємо rollback."
      perform_safe_rollback(tx)
    else
      # :pending або :unknown — ескалюємо до manual_review
      escalate_to_manual_review(tx, "tx_hash існує (#{tx.tx_hash}), але стан на блокчейні невідомий (#{receipt})")
    end
  end

  # Перевіряємо стан транзакції на блокчейні через RPC.
  # Повертає :confirmed, :reverted, :pending або :unknown
  #
  # [MULTICHAIN]: Solana використовує інший RPC-метод (getTransaction),
  # тому обробка відрізняється від EVM-мереж (eth_getTransactionReceipt).
  def fetch_transaction_receipt(tx)
    if tx.solana_network?
      fetch_solana_transaction_status(tx)
    else
      fetch_evm_transaction_receipt(tx)
    end
  rescue StandardError => e
    Rails.logger.error "🛑 [Web3] Не вдалося отримати receipt для TX ##{tx.id}: #{e.message}"
    :unknown
  end

  # EVM-мережі (Polygon, Celo): eth_getTransactionReceipt
  def fetch_evm_transaction_receipt(tx)
    rpc_env_key = tx.celo_network? ? "CELO_RPC_URL" : "ALCHEMY_POLYGON_RPC_URL"
    client = Web3::RpcConnectionPool.client_for(rpc_env_key,
                                                fallback: "https://polygon-rpc.com",
                                                fallback_env_keys: [ "INFURA_POLYGON_RPC_URL" ])
    receipt = client.eth_get_transaction_receipt(tx.tx_hash)

    if receipt.nil? || receipt == {}
      :pending
    elsif receipt["status"] == "0x1" || receipt["status"] == 1
      :confirmed
    else
      :reverted
    end
  end

  # Solana: JSON-RPC getTransaction
  # Solana не використовує eth gem, тому робимо HTTP-запит напряму.
  def fetch_solana_transaction_status(tx)
    solana_url = ENV.fetch("SOLANA_RPC_URL", nil)
    return :unknown unless solana_url

    response = Web3::HttpClient.post(solana_url,
      body: {
        jsonrpc: "2.0", id: 1, method: "getTransaction",
        params: [ tx.tx_hash, { encoding: "json", commitment: "confirmed" } ]
      },
      service_name: "Solana"
    )

    result = response.parsed_body&.dig("result")
    return :pending if result.nil?

    if result.dig("meta", "err").nil?
      :confirmed
    else
      :reverted
    end
  end

  # Безпечний rollback: тільки коли tx_hash ВІДСУТНІЙ (транзакція не покинула бекенд).
  def perform_safe_rollback(tx)
    Rails.logger.fatal "☠️ [Web3] Капітуляція транзакції ##{tx.id}. Запуск протоколу повернення активів..."

    ActiveRecord::Base.transaction do
      tx.wallet.with_lock do
        refund_points = tx.locked_points || (tx.amount * TokenomicsEvaluatorWorker::EMISSION_THRESHOLD).to_i

        if tx.wallet.locked_balance >= refund_points
          tx.wallet.release_locked_funds!(refund_points)
        elsif tx.wallet.locked_balance > 0
          tx.wallet.release_locked_funds!(tx.wallet.locked_balance)
        end

        # [SAFE NAVIGATION]: Захист від nil-рефренсу при видаленому дереві
        tree_did = tx.wallet.tree&.did || "N/A"
        tx.update!(
          status: :failed,
          notes: "Rollback: Постійний збій RPC. Розблоковано #{refund_points} балів для DID: #{tree_did}"
        )
      end
    end

    tx.wallet.broadcast_update if tx.wallet.respond_to?(:broadcast_update)
  end

  # Ескалація до ручної перевірки: кошти залишаються заблокованими,
  # транзакція переходить у manual_review, адмін отримує алерт.
  def escalate_to_manual_review(tx, reason)
    Rails.logger.warn "⚠️ [Web3] Ескалація TX ##{tx.id} до manual_review: #{reason}"

    tx.escalate_to_review!(reason)
  end
end
