# frozen_string_literal: true

class SolanaMicroRewardWorker
  include Sidekiq::Job

  # Solana мікро-винагороди мають найнижчий пріоритет серед Web3 операцій.
  # Вони не блокують критичний EVM (Polygon) мінтинг.
  # Retry: 3 спроби (Solana Devnet може бути нестабільним)
  sidekiq_options queue: "web3", retry: 3

  # [COMPOSITE PK]: telemetry_logs партиціоновано по created_at.
  # Передаємо обидва поля для ефективного partition pruning.
  def perform(telemetry_log_id, created_at_iso = nil)
    log = find_telemetry_log(telemetry_log_id, created_at_iso)
    return unless log

    Solana::MintingService.new(log).mint_micro_reward!

  rescue StandardError => e
    Rails.logger.error "🌊 [Solana] Micro-reward error для TelemetryLog ##{telemetry_log_id}: #{e.message}"
    raise e
  end

  private

  # [COMPOSITE PK]: Ефективний пошук з partition pruning
  def find_telemetry_log(telemetry_log_id, created_at_iso)
    scope = TelemetryLog.where(id: telemetry_log_id)

    if created_at_iso.present?
      begin
        scope = scope.where(created_at: Time.iso8601(created_at_iso))
      rescue ArgumentError
        # Некоректний формат — шукаємо без partition pruning
      end
    end

    log = scope.first
    Rails.logger.error "🛑 [Solana] TelemetryLog ##{telemetry_log_id} не знайдено." unless log
    log
  end
end
