# frozen_string_literal: true

# = ===================================================================
# 📦 MINT BATCH COLLECTOR WORKER (Scheduled Gas Optimization)
# = ===================================================================
# Періодично збирає pending BlockchainTransaction записи та відправляє
# їх пакетами через BlockchainMintingService.call_batch.
#
# Gas savings: batchMint(100) ≈ 30-40% дешевше ніж 100 × mint()
#
# Працює ПАРАЛЕЛЬНО з MintCarbonCoinWorker:
#   - MintCarbonCoinWorker: oracle-driven мінтинг (негайно після Chainlink callback)
#   - MintBatchCollectorWorker: планова оптимізація (зібрати та відправити пакетом)
#
# Запускається кожні 5 хвилин через Sidekiq scheduler.
class MintBatchCollectorWorker
  include ApplicationWeb3Worker
  sidekiq_options queue: "web3", retry: 3, lock: :until_executed

  def perform
    with_web3_error_handling("Polygon", "Batch Collector") do
      Treasury::MintBatchCollectorService.call
    end
  end
end
