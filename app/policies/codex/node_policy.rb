# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Codex::NodePolicy — RBAC matrix per docs/04_05_Codex_Lore_Module.md §5.
#
# Read: any authenticated user (Codex is the lore layer everybody can browse).
# Write: super_admin only — DAO-promoted submissions go through a separate
# governance flow (out of scope for Phase 1).
module Codex
  class NodePolicy < ApplicationPolicy
    def index?
      user.present?
    end

    def show?
      user.present?
    end

    def create?
      super_admin?
    end

    def update?
      super_admin?
    end

    def destroy?
      super_admin?
    end

    class Scope < ApplicationPolicy::Scope
      def resolve
        # Public Codex — no organisation scoping. Only published rows are
        # surfaced to non-admins; admins see drafts (published_at IS NULL).
        if super_admin?
          scope.all
        else
          scope.where.not(published_at: nil)
        end
      end
    end
  end
end
