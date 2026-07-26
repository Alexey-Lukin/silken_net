# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Codex::AttunementPolicy — anyone authenticated may toggle their own
# attunement; admins have no special powers here (an admin's attunement
# is still personal).
module Codex
  class AttunementPolicy < ApplicationPolicy
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
      record.user_id == user&.id
    end

    def destroy?
      record.user_id == user&.id
    end

    class Scope < ::ApplicationPolicy::Scope
      def resolve
        scope.all
      end
    end
  end
end
