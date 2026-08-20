# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [PERF.1(д)] Puro-анкер дістає ВЛАСНИЙ lifecycle-стан (присуд founder 2026-08-20:
# «третя форма» — прецедент EthereumAnchor, без грошової таблиці). Доти конфірмейшн-нога
# вела в `blockchain_transactions`, куди хеш паспорта не потрапляє НІКОЛИ, тож
# «доказ» віддавався в зовнішній реєстр Puro без перевірки, що транзакція не revert.
# nil = анкер ще не broadcast'ився (або запис не biomass_extraction).
class AddBiomassPassportStatusToMaintenanceRecords < ActiveRecord::Migration[8.1]
  def up
    add_column :maintenance_records, :biomass_passport_status, :string

    # Legacy-рядки з хешем без стану (до цієї міграції): доля невідома → :sent,
    # власний поллер довершить. У прод нуль таких (шлях activation-gated),
    # тож single-statement backfill безпечний — звідси safety_assured.
    safety_assured do
      execute <<~SQL
        UPDATE maintenance_records
        SET biomass_passport_status = 'sent'
        WHERE biomass_passport_tx_hash IS NOT NULL
      SQL
    end
  end

  def down
    remove_column :maintenance_records, :biomass_passport_status
  end
end
