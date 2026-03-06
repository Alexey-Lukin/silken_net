# frozen_string_literal: true

class EnhanceAuditLogs < ActiveRecord::Migration[8.1]
  def change
    change_table :audit_logs, bulk: true do |t|
      # Security Context — ідентифікація джерела дії (IP, браузер)
      t.string :ip_address
      t.string :user_agent
    end

    # Hot-Path: основний запит контролера — WHERE organization_id = ? ORDER BY created_at DESC
    add_index :audit_logs, [ :organization_id, :created_at ],
              name: "index_audit_logs_on_org_and_created",
              order: { created_at: :desc }

    # Scope .recent — ORDER BY created_at DESC по всій таблиці
    add_index :audit_logs, :created_at,
              name: "index_audit_logs_on_created_at",
              order: :desc

    # Security forensics — швидкий пошук за IP при розслідуванні інцидентів
    add_index :audit_logs, :ip_address,
              name: "index_audit_logs_on_ip_address",
              where: "ip_address IS NOT NULL"
  end
end
