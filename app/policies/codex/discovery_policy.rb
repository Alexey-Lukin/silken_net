# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Codex::DiscoveryPolicy — own collection only.
#
# Discoveries are a personal log: "what I have unlocked". The only mutator
# is `Codex::DiscoveryProbeWorker` (system-bot path) plus a manual unlock
# action gated behind `admin_or_above?` — which we model as `manual?`
# rather than `create?` to prevent rogue user-side POSTs from persisting
# fake unlocks.
module Codex
  class DiscoveryPolicy < Codex::ApplicationPolicy
    def index?
      user.present?
    end

    def show?
      user.present? && record.user_id == user.id
    end

    # System bots & admins only. End-users never call POST directly —
    # unlocks happen via DiscoveryProbeWorker.
    def create?
      admin_or_above?
    end

    def manual?
      admin_or_above?
    end

    class Scope < Codex::ApplicationPolicy::Scope
      def resolve
        return scope.none unless user

        scope.where(user_id: user.id)
      end
    end
  end
end
