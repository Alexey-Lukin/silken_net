# frozen_string_literal: true

# = ===================================================================
# 💰 TREASURY MONITOR WORKER (Scheduled Oracle Wallet Health Check)
# = ===================================================================
# Періодично перевіряє баланси Oracle-гаманців на всіх 4 мережах:
#   - Polygon (MATIC) — мінтинг SCC/SFC
#   - Solana (SOL) — мікро-винагороди USDC
#   - Celo (CELO) — community rewards cUSD
#   - Ethereum L1 (ETH) — state root anchoring
#
# Оновлює Prometheus gauges та створює EwsAlert при критичних балансах.
# Запускається кожні 15 хвилин через Sidekiq scheduler.
class TreasuryMonitorWorker
  include ApplicationWeb3Worker
  sidekiq_options queue: "web3_low", retry: 3, lock: :until_executed

  def perform
    with_web3_error_handling("Treasury", "Oracle Wallets") do
      results = Treasury::MonitorService.call

      healthy = results.count { |r| r[:status] == :healthy }
      critical = results.count { |r| r[:status] == :critical }
      errored = results.count { |r| r[:status] == :error }

      Rails.logger.info "💰 [Treasury] Monitor complete: " \
                        "#{healthy} healthy, #{critical} critical, #{errored} errors"
    end
  end
end
