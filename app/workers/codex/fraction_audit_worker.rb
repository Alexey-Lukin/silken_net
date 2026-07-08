# frozen_string_literal: true

# Codex::FractionAuditWorker — writes the AuditLog row for a fraction
# change off the user's request path.
#
# Skips users without an organization (e.g. the `oracle.executioner@system`
# bot): `audit_logs.organization_id` is NOT NULL, and the chained-hash
# ledger is per-org by design. A no-op is the right answer here — the
# Pundit-allowed user can still change their fraction; we just don't
# persist a multi-tenant ledger entry for orphans.
module Codex
  class FractionAuditWorker
    include Sidekiq::Worker

    sidekiq_options queue: :default, retry: 3

    AUDIT_ACTION = "codex.fraction.chosen"

    def perform(user_id, fraction_id, previous_node_id = nil)
      user     = ::User.find_by(id: user_id)
      fraction = ::Codex::Fraction.find_by(id: fraction_id)
      return unless user && fraction
      return unless user.organization_id

      ::AuditLog.create!(
        user_id: user.id,
        organization_id: user.organization_id,
        action: AUDIT_ACTION,
        auditable_type: "Codex::Fraction",
        auditable_id: fraction.id,
        metadata: {
          codex_node_id: fraction.codex_node_id,
          archetype_key: fraction.archetype_key,
          previous_node_id: previous_node_id,
          changed_at: fraction.last_changed_at.iso8601 # NOT NULL — persisted fraction завжди має мітку
        }
      )
    end
  end
end
