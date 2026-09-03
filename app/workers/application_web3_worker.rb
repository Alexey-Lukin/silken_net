# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# = ===================================================================
# 🌐 APPLICATION WEB3 WORKER (Base Module for All Blockchain Workers)
# = ===================================================================
# Централізований фундамент для всіх Web3/blockchain воркерів SilkenNet.
# Забезпечує:
# - Стандартизовану обробку RPC-помилок (timeouts, connection failures)
# - Структуроване логування з ідентифікацією мережі
# - Загальні хелпери (partition-pruned TelemetryLog lookup)
# - Дефолтні Sidekiq-опції для Web3 черг
#
# Використання:
#   class MyCryptoWorker
#     include ApplicationWeb3Worker
#     sidekiq_options queue: "web3_critical", retry: 10  # Override defaults
#
#     def perform(...)
#       with_web3_error_handling("Polygon", "TX ##{tx_id}") do
#         # RPC call
#       end
#     end
#   end
module ApplicationWeb3Worker
  extend ActiveSupport::Concern

  # Стандартні RPC-помилки, що виникають при взаємодії з блокчейн-нодами.
  # Ці помилки є тимчасовими (transient) і завжди повинні ретраїтись через Sidekiq.
  # Включає як HTTPX-специфічні помилки (основний HTTP-клієнт), так і
  # Net::HTTP-помилки (для сумісності з бібліотеками, що можуть їх кидати).
  RPC_TRANSIENT_ERRORS = [
    HTTPX::TimeoutError,
    HTTPX::ConnectionError,
    Net::OpenTimeout,
    Net::ReadTimeout,
    Errno::ECONNREFUSED,
    Errno::ECONNRESET,
    IOError
  ].freeze

  included do
    include Sidekiq::Job
    sidekiq_options queue: "web3", retry: 5
  end

  # [SIDEKIQ ENTERPRISE]: Глобальний RPC Rate Limiter.
  # Обмежує ВСІХ Web3 воркерів до 50 запитів/секунду сумарно.
  # Захищає від HTTP 429 (Too Many Requests) від Alchemy/Infura/QuickNode.
  #
  # В production: Sidekiq Enterprise використовує Redis для розподіленого
  # лімітування між усіма процесами Sidekiq (Heroku/Kamal dyno'ами).
  # В test/dev: shim з config/initializers/sidekiq_pro.rb просто виконує блок.
  #
  # wait: 5 означає, що воркер чекатиме до 5 секунд на вільний слот,
  # перш ніж кинути Sidekiq::Limiter::OverLimit (яку Enterprise middleware
  # автоматично перетворює на reschedule).
  WEB3_RPC_LIMITER = Sidekiq::Limiter.window("web3_rpc", 50, :second, wait: 5)

  # Обгортка для RPC-взаємодій з блокчейном.
  # [RATE LIMITED]: Автоматично обмежує частоту RPC-запитів через Enterprise Limiter.
  # Забезпечує уніфіковане логування та гарантує re-raise для Sidekiq retry.
  #
  # @param chain_name [String] назва мережі для логування (e.g., "Polygon", "Celo", "Solana")
  # @param resource_info [String, nil] опціональний контекст ресурсу (e.g., "TX #123", "Wallet #456")
  # @yield блок з RPC-операціями
  def with_web3_error_handling(chain_name, resource_info = nil)
    within_rpc_limit do
      yield
    end
  rescue Sidekiq::Limiter::OverLimit
    # Sidekiq Enterprise middleware автоматично перепланує джобу.
    context = resource_info ? " for #{resource_info}" : ""
    Rails.logger.warn "⏱️ [#{chain_name}] RPC rate limit exceeded#{context}. Job rescheduled by Enterprise."
    raise
  rescue HTTPX::TimeoutError => e
    SilkenNet::Metrics::RPC_ERRORS_TOTAL.increment(labels: { network: chain_name, error_type: "timeout" })
    log_web3_error("⏱️", chain_name, "RPC Timeout", resource_info, e)
    raise
  rescue HTTPX::ConnectionError => e
    SilkenNet::Metrics::RPC_ERRORS_TOTAL.increment(labels: { network: chain_name, error_type: "connection" })
    log_web3_error("🔌", chain_name, "RPC Connection Error", resource_info, e)
    raise
  rescue Net::OpenTimeout, Net::ReadTimeout => e
    SilkenNet::Metrics::RPC_ERRORS_TOTAL.increment(labels: { network: chain_name, error_type: "timeout" })
    log_web3_error("⏱️", chain_name, "RPC Timeout", resource_info, e)
    raise
  rescue Errno::ECONNREFUSED, Errno::ECONNRESET, IOError => e
    SilkenNet::Metrics::RPC_ERRORS_TOTAL.increment(labels: { network: chain_name, error_type: "connection" })
    log_web3_error("🔌", chain_name, "RPC Connection Error", resource_info, e)
    raise
  end

  # Хелпер для прямого доступу до Enterprise Rate Limiter.
  # Використовується воркерами, що не викликають with_web3_error_handling
  # (MintCarbonCoinWorker, BlockchainConfirmationWorker, EthereumAnchorConfirmationWorker,
  # InsurancePayoutWorker).
  #
  # @yield блок з RPC-операціями
  def within_rpc_limit(&block)
    WEB3_RPC_LIMITER.within_limit(&block)
  end

  # [COMPOSITE PK]: Уніфікований пошук TelemetryLog з partition pruning.
  # Використовується воркерами, що обробляють телеметрію (Solana, Chainlink, IoTeX, Mint).
  #
  # @param telemetry_log_id [Integer] ID запису телеметрії
  # @param created_at_iso [String, nil] ISO 8601 timestamp для partition pruning
  # @param log_prefix [String] префікс для логування (e.g., "[Solana]", "[Chainlink]")
  # @return [TelemetryLog, nil]
  def find_telemetry_log_with_pruning(telemetry_log_id, created_at_iso, log_prefix: "[Web3]")
    # [S6.16] pruning-логіка (1с-вікно + degraded-облік) — One-Home
    # `TelemetryLog.partition_pruned`; тут лише id-scope і error-лог.
    log = TelemetryLog.where(id: telemetry_log_id)
                      .partition_pruned(created_at_iso, metric_caller: "ApplicationWeb3Worker")
                      .first
    Rails.logger.error "🛑 #{log_prefix} TelemetryLog ##{telemetry_log_id} не знайдено." unless log
    log
  end

  # [COMPOSITE PK]: Partition-pruned lookup for BlockchainTransaction.
  # blockchain_transactions is RANGE-partitioned by created_at with composite PK (id, created_at).
  # Without created_at in WHERE, PostgreSQL scans ALL partitions (Global Partition Scan).
  #
  # @param blockchain_transaction_id [Integer] ID транзакції
  # @param created_at_iso [String, nil] ISO 8601 timestamp для partition pruning
  # @param log_prefix [String] префікс для логування
  # @return [BlockchainTransaction, nil]
  def find_blockchain_tx_with_pruning(blockchain_transaction_id, created_at_iso, log_prefix: "[Web3]")
    tx = BlockchainTransaction.find_with_partition_pruning(blockchain_transaction_id, created_at_iso)
    tx
  rescue ActiveRecord::RecordNotFound
    Rails.logger.error "🛑 #{log_prefix} BlockchainTransaction ##{blockchain_transaction_id} не знайдено."
    nil
  end

  private

  def log_web3_error(icon, chain_name, error_type, resource_info, exception)
    context = resource_info ? " for #{resource_info}" : ""
    Rails.logger.error "#{icon} [#{chain_name}] #{error_type}#{context}: #{exception.message}"
  end
end
