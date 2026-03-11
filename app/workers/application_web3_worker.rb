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
  RPC_TRANSIENT_ERRORS = [
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

  # Обгортка для RPC-взаємодій з блокчейном.
  # Забезпечує уніфіковане логування та гарантує re-raise для Sidekiq retry.
  #
  # @param chain_name [String] назва мережі для логування (e.g., "Polygon", "Celo", "Solana")
  # @param resource_info [String, nil] опціональний контекст ресурсу (e.g., "TX #123", "Wallet #456")
  # @yield блок з RPC-операціями
  def with_web3_error_handling(chain_name, resource_info = nil)
    yield
  rescue Net::OpenTimeout, Net::ReadTimeout => e
    log_web3_error("⏱️", chain_name, "RPC Timeout", resource_info, e)
    raise
  rescue Errno::ECONNREFUSED, Errno::ECONNRESET, IOError => e
    log_web3_error("🔌", chain_name, "RPC Connection Error", resource_info, e)
    raise
  end

  # [COMPOSITE PK]: Уніфікований пошук TelemetryLog з partition pruning.
  # Використовується воркерами, що обробляють телеметрію (Solana, Chainlink, IoTeX, Streamr, Mint).
  #
  # @param telemetry_log_id [Integer] ID запису телеметрії
  # @param created_at_iso [String, nil] ISO 8601 timestamp для partition pruning
  # @param log_prefix [String] префікс для логування (e.g., "[Solana]", "[Chainlink]")
  # @return [TelemetryLog, nil]
  def find_telemetry_log_with_pruning(telemetry_log_id, created_at_iso, log_prefix: "[Web3]")
    scope = TelemetryLog.where(id: telemetry_log_id)

    if created_at_iso.present?
      begin
        scope = scope.where(created_at: Time.iso8601(created_at_iso))
      rescue ArgumentError
        # Некоректний формат — шукаємо без partition pruning
      end
    end

    log = scope.first
    Rails.logger.error "🛑 #{log_prefix} TelemetryLog ##{telemetry_log_id} не знайдено." unless log
    log
  end

  private

  def log_web3_error(icon, chain_name, error_type, resource_info, exception)
    context = resource_info ? " for #{resource_info}" : ""
    Rails.logger.error "#{icon} [#{chain_name}] #{error_type}#{context}: #{exception.message}"
  end
end
