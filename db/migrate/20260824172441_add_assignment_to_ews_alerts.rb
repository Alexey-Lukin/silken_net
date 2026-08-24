# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [E.20] «Хто зараз на гачку» — поруч із наявним `resolved_by` («хто закрив»).
# Доти схема вміла записати лише ДРУГЕ, тож питання адресата було структурно
# невиразним: `EwsAlert.escalate_field_audit!` мав дванадцять продюсерів і жодного
# споживача, що призначає або виконує.
#
# `assigned_at` окремою колонкою, а не деривацією з `updated_at`: саме різниця
# `assigned_at − created_at` робить виразним Кат-A-сигнал `05_05 §2`
# «неприєднання Forester'а до інциденту в SLA», у якого сьогодні немає референта
# в коді. ⚠️ Сам ПОРІГ SLA тут не з'являється — він лишається ⚖️.
#
# Індекс, якого немає в сиблінга `resolved_by`, доданий свідомо: природний запит
# диспетчеризації — «мої відкриті тривоги» і «нічиї», тобто саме по цій колонці.
# 🔴 ПЕРША міграція поверх squash-анкера, тож її форма задає прецедент. Взято
# safe-форму `strong_migrations` (concurrent-індекс + FK у два кроки), а НЕ
# `safety_assured`: остання була б твердженням про МАЙБУТНЄ («таблиця буде мала,
# коли це виконається»), якого ніхто не може гарантувати, тоді як safe-форма
# правильна в кожному сценарії й коштує три рядки. `disable_ddl_transaction!` —
# вимога concurrent-індексу, не вибір.
class AddAssignmentToEwsAlerts < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_column :ews_alerts, :assigned_to_id, :bigint, null: true
    add_column :ews_alerts, :assigned_at, :datetime, null: true

    add_index :ews_alerts, [ :assigned_to_id, :status ], algorithm: :concurrently

    add_foreign_key :ews_alerts, :users, column: :assigned_to_id, validate: false
    reversible { |dir| dir.up { validate_foreign_key :ews_alerts, column: :assigned_to_id } }
  end
end
