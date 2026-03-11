# frozen_string_literal: true

class SolanaMicroRewardWorker
  include ApplicationWeb3Worker

  # Solana мікро-винагороди мають найнижчий пріоритет серед Web3 операцій.
  # Вони не блокують критичний EVM (Polygon) мінтинг.
  # Retry: 3 спроби (Solana Devnet може бути нестабільним)
  sidekiq_options queue: "web3", retry: 3

  # [COMPOSITE PK]: telemetry_logs партиціоновано по created_at.
  # Передаємо обидва поля для ефективного partition pruning.
  def perform(telemetry_log_id, created_at_iso = nil)
    log = find_telemetry_log_with_pruning(telemetry_log_id, created_at_iso, log_prefix: "[Solana]")
    return unless log

    with_web3_error_handling("Solana", "TelemetryLog ##{telemetry_log_id}") do
      Solana::MintingService.new(log).mint_micro_reward!
    end
  end
end
