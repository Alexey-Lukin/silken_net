class AddL1AnchorTxHashToAuditLogs < ActiveRecord::Migration[8.1]
  def change
    add_column :audit_logs, :l1_anchor_tx_hash, :string
    add_index :audit_logs, :l1_anchor_tx_hash
  end
end
