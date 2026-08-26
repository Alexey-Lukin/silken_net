# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [SLASH-1] Момент переходу дерева в термінальний статус — носій для `dead_count`
# у `BlockchainBurningService#calculate_damage_ratio`.
#
# ЧОМУ ВЛАСНА КОЛОНКА, а не наявний носій (виміряно 2026-08-26, три кандидати):
#   • `AuditLog` — `Tree` НЕ включає `Auditable`, тож рядків про смерть дерева не
#     існує взагалі; плюс запис асинхронний (лаг черги через опівніч переносить
#     смерть в іншу добу) і fail-open без `oracle_executioner`.
#   • `MaintenanceRecord` — покриває `deceased` чесно (`attested_at`, одна
#     транзакція з `declare_deceased!`), але для `removed` єдина доступна дата це
#     `performed_at`, яку ВВОДИТЬ ОПЕРАТОР (валідація лише `<= Time.current`).
#     🔴 На грошовому шляху це клієнт-контрольований ЧИСЕЛЬНИК: подати демонтажі з
#     датою поза вікном — і `dead_count` доби дорівнює нулю. Не сурогат моменту, а вектор.
#   • `updated_at` — шумний в обидва боки: бампається на будь-який update, а
#     `mark_seen!`/стрес ідуть `update_all`/`update_column` і його обходять.
#
# ОДНА колонка, не пара `deceased_at`/`removed_at`: обидва мертві стани ТЕРМІНАЛЬНІ
# (в `Tree` aasm-блоці подій `from: :removed`/`from: :deceased` немає жодної), тож
# двох дат смерті не буває, а читач однаково гейтується статусом.
#
# ⛔ Індексу свідомо НЕМА: `index_trees_on_cluster_id_and_status` уже дає 2 з 3
# колонок предиката (`cluster_id` + `status IN (removed, deceased)`), а фільтр по
# даті лягає в heap на дереві кластера. Прецедент відмови без виміру —
# `AddDirectionToBlockchainTransactions` (2026-08-25).
#
# ⛔ Backfill НЕМАЄ і не може бути чесним: історичні burn'и термінальні
# (`NaasContract :breached`), формула працює вперед; для `removed` дати не існує
# нізвідки, тож NULL тут чесніший за реконструкцію.
class AddStatusChangedAtToTrees < ActiveRecord::Migration[8.1]
  def change
    add_column :trees, :status_changed_at, :datetime, null: true
  end
end
