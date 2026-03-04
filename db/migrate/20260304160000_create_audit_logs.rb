# frozen_string_literal: true

class CreateAuditLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :audit_logs do |t|
      t.references :user, null: false, foreign_key: true
      t.references :organization, null: false, foreign_key: true
      t.string :action, null: false
      t.string :auditable_type
      t.bigint :auditable_id
      t.jsonb :metadata, default: {}
      t.timestamps
    end

    add_index :audit_logs, [ :auditable_type, :auditable_id ], name: "index_audit_logs_on_auditable"
    add_index :audit_logs, :action
  end
end
