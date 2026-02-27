# frozen_string_literal: true

class BurnCarbonTokensWorker
  include Sidekiq::Job

  # Використовуємо ту саму чергу для повільних блокчейн-операцій
  sidekiq_options queue: "web3", retry: 5

  def perform(organization_id, naas_contract_id)
    Rails.logger.warn "🔥 [D-MRV Slashing] Ініціація протоколу спалювання для Контракту ##{naas_contract_id}"

    # 1. Екзекуція в Web3 (Незворотне спалювання SCC токенів)
    BlockchainBurningService.call(organization_id, naas_contract_id)

    # 2. СИНХРОНІЗАЦІЯ ІСТИНИ (DB State)
    # Якщо BlockchainBurningService не викинув помилку, значить транзакція в Polygon підтверджена.
    # Тепер ми маємо вбити контракт у нашій базі, щоб дашборд інвестора відобразив реальність.
    naas_contract = NaasContract.find_by(id: naas_contract_id)
    
    if naas_contract
      # Переводимо контракт у статус :terminated (або :slashed, залежно від твого enum)
      naas_contract.update!(status: :terminated)
      
      Rails.logger.info "🪦 [D-MRV] Контракт ##{naas_contract_id} офіційно розірвано (Terminated) після Slashing-у."
    end

  rescue StandardError => e
    # Якщо Alchemy або Polygon впали, Sidekiq зловить цю помилку і зробить retry (до 5 разів).
    # Контракт залишиться "активним", поки спалювання не пройде фізично.
    Rails.logger.error "🚨 [D-MRV Slashing] Помилка спалювання для Контракту ##{naas_contract_id}: #{e.message}"
    raise e
  end
end
