# frozen_string_literal: true

class BurnCarbonTokensWorker
  include Sidekiq::Job
  # 5 ретраїв з експоненціальною паузою для Polygon RPC
  sidekiq_options queue: "web3", retry: 5

  def perform(organization_id, naas_contract_id)
    naas_contract = NaasContract.find_by(id: naas_contract_id)
    return Rails.logger.error "🛑 [Slashing] Контракт ##{naas_contract_id} не знайдено." unless naas_contract

    cluster = naas_contract.cluster
    organization = naas_contract.organization

    Rails.logger.warn "🔥 [Slashing Protocol] Виконання вироку для #{organization.name} (Кластер: #{cluster.name})."

    # 1. WEB3 ЕКЗЕКУЦІЯ
    # Цей сервіс — наш "Меч". Він взаємодіє зі смарт-контрактом і спалює токени.
    # [СИНХРОНІЗОВАНО]: Ми припускаємо, що сервіс повертає tx_hash або кидає помилку.
    BlockchainBurningService.call(organization_id, naas_contract_id)

    # 2. СИНХРОНІЗАЦІЯ ІСТИННИ (Atomic Audit)
    # Поєднуємо зміну статусу та створення "надгробного каменю" в журналі.
    ActiveRecord::Base.transaction do
      naas_contract.update!(status: :breached)

      # Шукаємо системного користувача або адміна для запису
      executioner = User.find_by(role: :admin) || User.first

      MaintenanceRecord.create!(
        maintainable: cluster,
        user: executioner,
        action_type: :decommissioning, # "Фінансове списання" сектора
        notes: <<~NOTES
          🚨 SLASHING COMPLETED: Контракт ##{naas_contract_id} анульовано.#{' '}
          Вуглецеві активи спалено через критичну деградацію екосистеми.#{' '}
          Вердикт Оракула: BREACHED.
        NOTES
      )
    end

    # 3. СПОВІЩЕННЯ (The Cry of the Forest)
    broadcast_slashing_event(naas_contract)

    Rails.logger.info "🪦 [D-MRV] Контракт ##{naas_contract_id} офіційно анігільовано в системі."
  rescue StandardError => e
    Rails.logger.error "🚨 [Slashing Error] Провал місії для контракту ##{naas_contract_id}: #{e.message}"
    # Sidekiq перехопить це і запланує наступну спробу (retry 5)
    raise e
  end

  private

  def broadcast_slashing_event(contract)
    payload = {
      event: "CONTRACT_SLASHED",
      contract_id: contract.id,
      cluster_id: contract.cluster_id,
      organization_id: contract.organization_id,
      severity: :critical,
      message: "Критичне порушення! Контракт розірвано, активи інвестора вилучено.",
      timestamp: Time.current.to_i
    }

    # Синхронізована назва каналу з AlertNotificationWorker
    ActionCable.server.broadcast("org_#{contract.organization_id}_alerts", payload)
  end
end
