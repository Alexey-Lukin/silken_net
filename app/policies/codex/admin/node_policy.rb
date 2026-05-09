# frozen_string_literal: true

# Codex::Admin::NodePolicy — Phase 6 RBAC for the admin Node CRUD surface.
#
# Read access to the registry is admin+ (UI for moderation lives behind
# `/api/v1/codex/admin/nodes`). End-user read happens via the public
# `Codex::NodePolicy`, which scopes to published rows.
#
# Asymmetric write surface:
#   * `index?` / `show?`   → admin+ (DAO moderation UI)
#   * `update?`            → admin+ (publish toggle, geo correction, copy fix)
#   * `create?` / `destroy?` → super_admin only (Atlas Foundation seeds are
#     immutable; only Architects mint or retire lore at protocol scope)
module Codex
  module Admin
    class NodePolicy < ApplicationPolicy
      def index?
        admin_or_above?
      end

      def show?
        admin_or_above?
      end

      def create?
        super_admin?
      end

      def update?
        admin_or_above?
      end

      def destroy?
        super_admin?
      end

      class Scope < ApplicationPolicy::Scope
        def resolve
          return scope.none unless user
          return scope.none unless admin_or_above?

          scope.all
        end
      end
    end
  end
end
