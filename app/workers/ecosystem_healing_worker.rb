# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class EcosystemHealingWorker
  include Sidekiq::Job
  # Відновлення екосистеми після EWS-тривог є критичною операцією:
  # реанімація актуаторів, зняття з експлуатації, закриття тривог.
  sidekiq_options queue: "critical", retry: 3

  def perform(record_id)
    record = MaintenanceRecord.find(record_id)
    target = record.maintainable

    ActiveRecord::Base.transaction do
      # 1. ОСВІЖЕННЯ ПУЛЬСУ
      target.mark_seen! if target.respond_to?(:mark_seen!)

      # 2. РЕАНІМАЦІЯ АКТУАТОРІВ
      # [SAFETY]: guard may_deactivate? — repair-запис на вже-idle актуаторі
      # (preventive maintenance) інакше кидав AASM::InvalidTransition (mark_idle! =
      # deactivate!, валідний лише from active/offline/maintenance_needed) →
      # транзакція відкочувалась → alert.resolve! (крок 4) недосяжний → retry→dead.
      if target.is_a?(Actuator) && record.action_type_repair? && target.may_deactivate?
        target.mark_idle!
      end

      # 3. ЖИТТЄВИЙ ЦИКЛ ДЕРЕВА
      if target.is_a?(Tree) && record.action_type_decommissioning? && target.may_decommission?
        target.decommission!
      end

      # 🔴 [ARCH.76] Виведення з експлуатації має життєвий цикл ЛИШЕ в Дерева.
      # У Королеви enum — операційна петля без точки виходу
      # (idle/active/updating/maintenance/faulty), тож `decommissioning` на
      # шлюз доти створювався, валідувався й НЕ РОБИВ НІЧОГО: журнал стверджував
      # дію, якої не сталося ([FW.63]-клас на trust-поверхні).
      #
      # Рядок гучний СВІДОМО, і термінального стану замість нього не додано
      # (присуд власника 2026-08-14): відкликання довіри Королеви без фізичного
      # re-provision є театром — вкрадений шлюз тримає у флеші CoAP-ключ,
      # QATT-seed і KEYB УСЬОГО кластера, а `rotate_gateway_random!` із
      # Dual-Key Grace такого не гасить. Поле вирішує, як це має виглядати —
      # тим самим заходом, що й порядок паління option bytes (`00_07` 🚦 Critical
      # Path, рядок «Перед польовим деплоєм»); доти чесніша гучна відмова, ніж
      # тихий успіх. Присуд і його підстава → `00_07 §🗄️` ARCH.76.
      if target.is_a?(Gateway) && record.action_type_decommissioning?
        Rails.logger.error(
          "[ARCH.76] `decommissioning` на Gateway ##{target.id} — життєвого циклу " \
          "виведення в шлюза НЕМАЄ, запис ##{record.id} НЕ змінив стан пристрою"
        )
      end

      # 3a. AFTERLIFE ECONOMY (Puro.earth Biochar D-MRV)
      # Biomass extraction marks the tree dead; the D-MRV Biomass Passport that
      # anchors provenance on-chain is filed later, on attestation.
      # 🔴 [E.20, ⚖️ 2026-08-24] Тут ЛИШЕ смерть дерева. Паспорт у чергу ставить
      # `MaintenanceRecord#attest!` — пускачем незворотної заявки є сам підпис;
      # підстава й вимір ≈7–10 хв — картка воркера `04_02 §11` + скіл `backend` #77.
      if target.is_a?(Tree) && record.action_type_biomass_extraction?
        target.declare_deceased! unless target.deceased?
      end

      # 4. [ВИПРАВЛЕНО]: ЗАКРИТТЯ ТРИВОГИ (Enum Method Fix)
      # Тепер використовуємо status_resolved? замість resolved?
      alert = record.ews_alert
      if alert.present? && !alert.status_resolved?
        # [I18N.1] Ключ замість зашитої укр. прози з `.humanize`-токеном усередині:
        # тип дії у фразу НЕ інтерпольовано свідомо — його видно з самого запису
        # за `record_id`, а сирий enum у перекладеному реченні — окремий клас.
        alert.resolve!(user: record.user, key: "maintenance_restored",
                       params: { record_id: record.id })
      end
    end
  end
end
