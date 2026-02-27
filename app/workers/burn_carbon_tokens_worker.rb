# frozen_string_literal: true

class BurnCarbonTokensWorker
  include Sidekiq::Job
  # Web3-операції можуть бути повільними, тому 5 ретраїв - це розумний баланс
  sidekiq_options queue: "web3", retry: 5

  def perform(organization_id, naas_contract_id)
    naas_contract = NaasContract.find_by(id: naas_contract_id)
    unless naas_contract
      Rails.logger.error "🛑 [D-MRV Slashing] Контракт ##{naas_contract_id} не знайдено."
      return
    end

    Rails.logger.warn "🔥 [Slashing Protocol] Початок спалювання активів для #{naas_contract.cluster.name}..."

    # 1. ЕКЗЕКУЦІЯ В WEB3
    # BlockchainBurningService викликає функцію slash() у смарт-контракті Polygon
    BlockchainBurningService.call(organization_id, naas_contract_id)

    # 2. СИНХРОНІЗАЦІЯ ІСТИНИ
    # [ЗМІНА]: Використовуємо статус :breached, узгоджений з моделлю NaasContract
    ActiveRecord::Base.transaction do
      naas_contract.update!(status: :breached)
      
      # Залишаємо відбиток у журналі робіт (для аудиту лісником)
      MaintenanceRecord.create!(
        maintainable: naas_contract.cluster,
        user: User.find_by(role: :admin), # Системний запис
        action_type: :system_adjustment,
        action_taken: "SLASHING COMPLETED: Контракт ##{naas_contract_id} розірвано через порушення гомеостазу."
      )
    end

    # 3. СПОВІЩЕННЯ (The Sound of Silence)
    # Миттєво оновлюємо дашборд інвестора
    broadcast_slashing_event(naas_contract)

    Rails.logger.info "🪦 [D-MRV] Контракт ##{naas_contract_id} офіційно переведено у стан BREACHED."
  rescue StandardError => e
    Rails.logger.error "🚨 [Slashing Error] Спроба спалювання для контракту ##{naas_contract_id} провалилася: #{e.message}"
    raise e # Sidekiq повторить через деякий час
  end

  private

  def broadcast_slashing_event(contract)
    payload = {
      event: "CONTRACT_SLASHED",
      contract_id: contract.id,
      cluster_name: contract.cluster.name,
      message: "УВАГА: Контракт розірвано. Токени спалено.",
      timestamp: Time.current.to_i
    }
    
    ActionCable.server.broadcast("organization_#{contract.organization_id}_alerts", payload)
  end
end
