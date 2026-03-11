class AddIpfsCidToAuditLogs < ActiveRecord::Migration[8.1]
  def change
    add_column :audit_logs, :ipfs_cid, :string
  end
end
