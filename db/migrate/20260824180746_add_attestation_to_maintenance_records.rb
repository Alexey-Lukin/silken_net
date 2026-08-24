# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [E.20] «Атестатор ≠ бенефіціар» — друга пара очей на записі обслуговування.
#
# ⚖️ Присуд founder 2026-08-24: акаунт атестатора живе В організації власника, а
# незалежність купується ДОГОВОРОМ (сторонній аудитор / академічний партнер, якому
# платить не бенефіціар). Виміряна підстава відкинути буквальну форму «організація
# атестатора ≠ організація власника»: читацький скоуп записів деривується з
# `acting_organization!.clusters`, а перемикати контекст організації вміє лише
# `super_admin` — тобто атестатор із чужої орг запису НЕ БАЧИТЬ, і щоб він міг
# засвідчити, довелось би пробити крос-тенантне читання. Це не колонка, це діра в
# ізоляції — тій самій, у якій жив ланцюг account-takeover.
#
# Тому в коді лишається рівно ОДИН машинно-перевірний інваріант: підписант ≠ автор
# запису. Решту незалежності тримає договір, і канон це каже прямо.
class AddAttestationToMaintenanceRecords < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_column :maintenance_records, :attested_by_id, :bigint, null: true
    add_column :maintenance_records, :attested_at, :datetime, null: true

    add_index :maintenance_records, :attested_by_id, algorithm: :concurrently

    add_foreign_key :maintenance_records, :users, column: :attested_by_id, validate: false
    reversible { |dir| dir.up { validate_foreign_key :maintenance_records, column: :attested_by_id } }
  end
end
