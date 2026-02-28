# frozen_string_literal: true

class BurnCarbonTokensWorker
  include Sidekiq::Job
  # Web3-операції потребують терпіння. 5 ретраїв — золотий стандарт для Polygon RPC.
  sidekiq_options queue: "web3", retry: 5

  def perform(organization_id, naas_contract_id)
    naas_contract = NaasContract.find_by(id: naas_contract_id)
    unless naas_contract
      Rails.logger.error "🛑 [D-MRV Slashing] Контракт ##{naas_contract_id} не знайдено."
      return
    end

    Rails.logger.warn "🔥 [Slashing Protocol] Початок спалювання активів для сектору #{naas_contract.cluster.name}..."

    # 1. ЕКЗЕКУЦІЯ В WEB3
    # BlockchainBurningService викликає функцію slash() у смарт-контракті
    # Ми вже зашліфували цей сервіс, він готовий до бою.
    BlockchainBurningService.call(organization_id, naas_contract_id)

    # 2. СИНХРОНІЗАЦІЯ ІСТИНИ (Atomic Update)
    ActiveRecord::Base.transaction do
      naas_contract.update!(status: :breached)
      
      # Залишаємо відбиток у журналі (MaintenanceRecord)
      # [СИНХРОНІЗАЦІЯ]: Використовуємо :decommissioning як найбільш близький за змістом 
      # або готуємось додати :system_event в модель.
      MaintenanceRecord.create!(
        maintainable: naas_contract.cluster,
        user: User.find_by(role: :admin), # Системний акцепт
        action_type: :decommissioning, 
        notes: "🚨 SLASHING COMPLETED: Контракт ##{naas_contract_id} розірвано. Вуглецеві активи інвестора спалено через критичне порушення стану лісу."
      )
    end

    # 3. СПОВІЩЕННЯ (The Sound of Silence)
    # [СИНХРОНІЗАЦІЯ]: Використовуємо канал org_#{id}, як у AlertNotificationWorker
    broadcast_slashing_event(naas_contract)

    Rails.logger.info "🪦 [D-MRV] Контракт ##{naas_contract_id} офіційно переведено у стан BREACHED."
  rescue StandardError => e
    Rails.logger.error "🚨 [Slashing Error] Провал місії для контракту ##{naas_contract_id}: #{e.message}"
    raise e 
  end

  private

  def broadcast_slashing_event(contract)
    payload = {
      event: "CONTRACT_SLASHED",
      contract_id: contract.id,
      cluster_name: contract.cluster.name,
      severity: :critical,
      message: "УВАГА: Контракт розірвано. Активи спалено через деградацію екосистеми.",
      timestamp: Time.current.to_i
    }
    
    # Синхронізована назва каналу для фронтенду
    ActionCable.server.broadcast("org_#{contract.organization_id}_alerts", payload)
  end
end
