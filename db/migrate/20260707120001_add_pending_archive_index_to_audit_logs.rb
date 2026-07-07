# frozen_string_literal: true

# [INF.22 крок 11] Partial index для FilecoinReconcileWorker: дзеркалить ТОЧНО reconcile-предикат
# `AuditLog.pending_archive` (archive-requested, ще не запінене) → лишається малим (обмежений
# transient money-backlog'ом, НЕ росте з never-eligible codex/factory-логами назавжди — саме
# тому предикат, а не голий `ipfs_cid IS NULL`). audit_logs НЕ партиційована (лінійний ріст із
# money-transitions) → concurrently обов'язковий проти table-lock на масштабі.
class AddPendingArchiveIndexToAuditLogs < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :audit_logs, :archive_requested_at,
              where: "archive_requested_at IS NOT NULL AND ipfs_cid IS NULL",
              algorithm: :concurrently,
              name: "index_audit_logs_pending_archive"
  end
end
