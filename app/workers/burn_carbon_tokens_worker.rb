# frozen_string_literal: true

class BurnCarbonTokensWorker
  include Sidekiq::Job
  # Використовуємо чергу critical, бо фінансова відплата має бути негайною, 
  # щоб запобігти виводу токенів інвестором.
  sidekiq_options queue: "critical", retry: 5

  def perform(organization_id, naas_contract_id, tree_id = nil)
    naas_contract = NaasContract.find_by(id: naas_contract_id)
    return Rails.logger.error "🛑 [Slashing] Контракт ##{naas_contract_id} не знайдено." unless naas_contract

    organization = Organization.find(organization_id)
    cluster = naas_contract.cluster
    source_tree = Tree.find_by(id: tree_id) if tree_id

    Rails.logger.warn "🔥 [Slashing Protocol] Виконання вироку для #{organization.name} (Кластер: #{cluster.name})."

    # 1. WEB3 ЕКЗЕКУЦІЯ (The Judgment Stroke)
    # Передаємо source_tree як доказ порушення для логування в блокчейні.
    # Сервіс сам розрахує суму на основі підтвердженого гомеостазу.
    BlockchainBurningService.call(
      organization_id, 
      naas_contract_id, 
      source_tree: source_tree
    )

    # 2. СИНХРОНІЗАЦІЯ ІСТИННИ (Atomic Audit)
    # Ми маркуємо контракт як BREACHED вже всередині сервісу, але тут 
    # створюємо "надгробний камінь" у фізичному журналі обслуговування.
    ActiveRecord::Base.transaction do
      # Шукаємо системного інквізитора (Адміна) для підпису запису
      executioner = User.find_by(role: :admin) || User.first

      MaintenanceRecord.create!(
        maintainable: cluster,
        user: executioner,
        action_type: :decommissioning,
        notes: <<~NOTES
          🚨 SLASHING EXECUTED.
          Контракт ##{naas_contract_id} анульовано через порушення біо-цілісності.
          #{source_tree ? "Причина: Загибель Солдата #{source_tree.did}." : "Причина: Загальна деградація кластера."}
          Вердикт Оракула: BREACHED.
        NOTES
      )
    end

    # 3. СПОВІЩЕННЯ (The Cry of the Forest)
    # Транслюємо подію в реальному часі на всі Dashboards організації.
    broadcast_slashing_event(naas_contract, source_tree)

    Rails.logger.info "🪦 [D-MRV] Контракт ##{naas_contract_id} офіційно анігільовано в системі."
  rescue StandardError => e
    Rails.logger.error "🚨 [Slashing Error] Провал місії для контракту ##{naas_contract_id}: #{e.message}"
    # Sidekiq перехопить помилку для повторної спроби, якщо блокчейн був недоступний
    raise e
  end

  private

  def broadcast_slashing_event(contract, tree)
    payload = {
      event: "CONTRACT_SLASHED",
      contract_id: contract.id,
      cluster_id: contract.cluster_id,
      tree_did: tree&.did,
      severity: :critical,
      message: "УВАГА: Критичне порушення гомеостазу! Контракт розірвано, активи вилучено.",
      timestamp: Time.current.to_i
    }

    # Повідомляємо конкретну організацію через ActionCable
    ActionCable.server.broadcast("org_#{contract.organization_id}_alerts", payload)
    
    # Також оновлюємо UI контракту через Turbo Streams, якщо Архітектор дивиться на нього
    Turbo::StreamsChannel.broadcast_replace_to(
      contract,
      target: "contract_status_badge_#{contract.id}",
      html: "<span class='px-2 py-1 bg-red-900 text-red-200 rounded animate-pulse text-[10px] font-bold uppercase'>BREACHED</span>"
    )
  end
end
