# frozen_string_literal: true

# [INF.22 крок 11 — Filecoin archive outbox] `archive_requested_at` = явний outbox-маркер
# «цей AuditLog має жити на IPFS вічно». Виставляється ЛИШЕ money/MRV-шляхом (AuditLogWorker,
# у create-транзакції); codex/factory прямий `create!` його НЕ ставлять → природно поза
# archive-периметром (без крихкої евристики по auditable_type). Nullable, без default →
# safe metadata-only ALTER (миттєвий на Postgres 11+).
class AddArchiveRequestedAtToAuditLogs < ActiveRecord::Migration[8.1]
  def change
    add_column :audit_logs, :archive_requested_at, :datetime, null: true
  end
end
