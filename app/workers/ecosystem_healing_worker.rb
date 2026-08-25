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
      # ⛔ [ARCH.109] Тут НЕ місце `mark_seen!`, і повертати його не можна.
      # `last_seen_at` — канал живості САМОГО вузла; з нього виводять вердикт
      # `hardware_pulse_confirmed?` [UI.7], `Tree.silent` [SILENCE-1] і
      # `fresh_signal?` [ARCH.99]. Штамп на людському записі замикав ланцюг
      # однією парою рук: подав форму → платформа проставила пульс → підтвердив
      # «залізо відгукнулось». Пульс пишуть лише ті, хто справді почув вузол —
      # `TelemetryUnpackerService` (дерево) і `GatewayTelemetryWorker` (шлюз).
      # Підстава не інженерна, а місійна (`00_01 §1.1`): у вузла тут відбирали
      # не запис, а голос — тишу, яка єдина в цій системі не бреше.

      # 1. РЕАНІМАЦІЯ АКТУАТОРІВ
      # [SAFETY]: guard may_deactivate? — repair-запис на вже-idle актуаторі
      # (preventive maintenance) інакше кидав AASM::InvalidTransition (mark_idle! =
      # deactivate!, валідний лише from active/offline/maintenance_needed) →
      # транзакція відкочувалась → alert.resolve! (крок 4) недосяжний → retry→dead.
      if target.is_a?(Actuator) && record.action_type_repair? && target.may_deactivate?
        target.mark_idle!
      end

      # 2. ЖИТТЄВИЙ ЦИКЛ ДЕРЕВА
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

      # ⛔ [E.20, ⚖️ 2026-08-25] Смерть дерева тут БІЛЬШЕ не оголошується, і
      # повертати її сюди не можна. `declare_deceased!` термінальний — подій
      # `from: :deceased` немає жодної, — і тим самим переходом смикає
      # `trigger_slashing_protocol`. Тобто з заявки його виконувала ОДНА людина
      # одним рядком форми, без жодної передумови (ні тиші, ні стресу).
      # Тепер обидві незворотні дії — смерть і CORC-паспорт — має ОДИН пускач:
      # підпис другої пари очей (`MaintenanceRecord#attest!`, «атестатор ≠
      # бенефіціар»). Дерево, яке вже мовчить, не може заперечити за себе —
      # тому свідком тут мусить бути незалежна людина, а не автор заявки.

      # 3. ЗАКРИТТЯ ТРИВОГИ
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
