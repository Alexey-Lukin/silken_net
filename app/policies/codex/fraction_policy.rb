# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Codex::FractionPolicy — own-only writes; reads are public among
# authenticated users (so the Profile of another forester can show their
# fraction badge).
#
# Cooldown is enforced inside `Codex::FractionChangeService`, NOT here:
# Pundit answers "may this user act?", not "is the action permissible
# *right now*?" — the latter is a business-rule concern.
module Codex
  class FractionPolicy < Codex::ApplicationPolicy
    def index?
      user.present?
    end

    def show?
      user.present?
    end

    def create?
      user.present?
    end

    def update?
      owns_record?
    end

    def destroy?
      owns_record?
    end

    class Scope < Codex::ApplicationPolicy::Scope
      def resolve
        scope.all
      end
    end

    private

    def owns_record?
      return false unless user && record.respond_to?(:user_id)

      record.user_id == user.id
    end
  end
end
