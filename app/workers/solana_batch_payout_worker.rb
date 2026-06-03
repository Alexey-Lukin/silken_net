# frozen_string_literal: true

# = ===================================================================
# 🌊 SOLANA BATCH PAYOUT WORKER (Scheduled Gas Optimization) [E.61]
# = ===================================================================
# Періодично виплачує акумульовані Solana мікро-винагороди одним
# TransferChecked на гаманець через Solana::BatchPayoutService.
#
# Працює ПАРАЛЕЛЬНО з SolanaMicroRewardWorker:
#   - SolanaMicroRewardWorker: per-event виплата (поріг 0) АБО акумуляція в Kredis (поріг > 0)
#   - SolanaBatchPayoutWorker: планова виплата накопиченого (лише коли поріг > 0)
#
# lock: until_executed — щоб годинні запуски не накладались.
class SolanaBatchPayoutWorker
  include ApplicationWeb3Worker
  include Web3CircuitBreaker

  sidekiq_options queue: "web3", retry: 3, lock: :until_executed

  def perform
    with_circuit_breaker("solana_spl") do
      with_web3_error_handling("Solana", "Batch Payout") do
        Solana::BatchPayoutService.call
      end
    end
  rescue Web3CircuitBreaker::CircuitOpenError
    Rails.logger.warn "⚡ [Solana] Circuit OPEN — batch payout буде повторено пізніше."
    raise
  end
end
