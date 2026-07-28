# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [ARCH.57] Привілейовані дії → tamper-evident SHA-256 AuditLog-ланцюг (дзеркало MRV.1
# BlockchainTransaction#record_money_audit_trail). Хуки на model-рівні ловлять УСІ шляхи
# запису (controller, worker, console). organization_id: nil = глобальний системний
# ланцюг (org-less дії: SystemParameter). archive: false за замовчуванням — chain-only,
# без Filecoin/IPFS-піна (публічний IPFS не місце для security-метаданих; INF.22-периметр
# архівації лишається money/MRV — ті шляхи передають archive: true явно).
# Ланцюг вимагає актора (user_id NOT NULL) — без нього WARN-skip, дію НЕ валимо.
module Auditable
  extend ActiveSupport::Concern

  # Системний актор для дій без людського ініціатора. Лукап навмисно повторюваний
  # у батч-циклах — Prosopite-пауза за прецедентом AuditLog#compute_chain_hash.
  # `defined?(Prosopite)`-else = прод-шлях (Prosopite лише group :development,:test);
  # hide_const ламає глобальні Prosopite RSpec-хуки → лишаємо некритим (§B.4/§B.5 leave).
  def self.system_actor_id
    Prosopite.pause if defined?(Prosopite)
    User.oracle_executioner&.id
  ensure
    Prosopite.resume if defined?(Prosopite)
  end

  # ip_address/user_agent заповнюються лише там, де є request-контекст (майбутні
  # controller-виклики); system-шляхи пишуть порожньо — колонки все одно В хеші
  # (tamper-evident), тож задня підміна ламає verify_chain_integrity.
  def record_audit_trail!(action:, organization_id:, auditable: self, user_id: nil,
                          ip_address: nil, user_agent: nil, metadata: {}, archive: false)
    actor_id = user_id || Auditable.system_actor_id
    if actor_id.blank?
      Rails.logger.warn "📋 [ARCH.57] AuditLog skip #{action}: актор невідомий " \
                        "(oracle_executioner відсутній)"
      return
    end

    AuditLog.record_async!(
      {
        user_id: actor_id,
        organization_id: organization_id,
        action: action,
        auditable_type: auditable&.class&.name,
        auditable_id: auditable&.id,
        ip_address: ip_address,
        user_agent: user_agent,
        metadata: with_acting_context(metadata)
      },
      archive: archive
    )
  end

  private

  # [SEC.25 Ф2] Дія, виконана з ПЕРЕМКНУТОГО контексту, мусить нести це в сліді.
  # Інакше організація бачить наслідок (OTA-деплой, команду актуатору, зміну
  # налаштувань) і не бачить, що виконавець прийшов ззовні: сам факт перемикання
  # лежить окремим записом, і зшивати його з дією довелося б руками по часу.
  #
  # Мітка ставиться ТУТ, а не в п'ятьох названих екшенах, бо перелік «записуючих
  # дій» дрейфує з кожним новим ендпоінтом, а цей хук — єдиний спільний шов усіх
  # привілейованих мутацій.
  #
  # Порожньо для системних шляхів: Sidekiq `Current` не виставляє, тож відсутність
  # мітки читається як «системна дія», а не як загублений слід.
  def with_acting_context(metadata)
    return metadata unless Current.switched_context?

    metadata.merge(
      acting_organization_id: Current.acting_organization_id,
      actor_home_organization_id: Current.home_organization_id
    )
  end
end
