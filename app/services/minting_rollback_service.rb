# frozen_string_literal: true

# = ===================================================================
# 🔄 MINTING ROLLBACK SERVICE (The Absolute Integrity)
# = ===================================================================
# Відповідає за повернення заблокованих коштів після вичерпання всіх
# Sidekiq-ретраїв у MintCarbonCoinWorker. Запобігає "зависанню" капіталу
# у locked_balance, коли RPC Polygon перманентно недоступний.
#
# [ARCHITECTURAL FIX]: Ця логіка була вилучена з sidekiq_retries_exhausted
# блоку MintCarbonCoinWorker для дотримання принципу Single Responsibility
# та забезпечення тестованості та повторного використання.
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

    wallet.blockchain_transactions.where(status: [ :pending, :processing ])
  end

  def find_telemetry_log
    scope = TelemetryLog.where(id: @telemetry_log_id)
    if @created_at_iso.present?
      begin
        scope = scope.where(created_at: Time.iso8601(@created_at_iso))
      rescue ArgumentError
        # Некоректний формат — шукаємо без partition pruning
      end
    end
    scope.first
  end

  def rollback_transaction!(tx)
    # [GUARD]: Пропускаємо транзакції, що вже у термінальному стані
    return if tx.status.in?(%w[confirmed failed])

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
end
