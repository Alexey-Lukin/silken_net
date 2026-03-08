# frozen_string_literal: true

# Immutable Integrity Chain для AuditLog (Zone 1.3: Стіна масштабування)
#
# ПРОБЛЕМА: Логи можна змінити через SQL-ін'єкцію або недобросовісного адміна БД.
# Немає механізму перевірки цілісності.
#
# РІШЕННЯ: Кожен запис містить chain_hash = SHA-256(previous_chain_hash + payload).
# Це перетворює AuditLog на локальний блокчейн per organization.
# Будь-яка зміна будь-якого запису ламає ланцюг — виявляється верифікацією.
class AddChainHashToAuditLogs < ActiveRecord::Migration[8.1]
  def change
    add_column :audit_logs, :chain_hash, :string

    # Індекс для швидкого пошуку останнього запису в ланцюгу організації
    # Використовується в before_create для побудови chain_hash
    add_index :audit_logs, [ :organization_id, :id ],
              name: "index_audit_logs_on_org_id_and_id",
              order: { id: :desc }
  end
end
