# frozen_string_literal: true

# Codex::ApplicationPolicy — small base class for all Codex policies.
# Centralises common helpers (admin tier, ownership) and provides safe
# defaults: read-all for any authenticated user, writes denied unless
# explicitly enabled by the subclass.
module Codex
  class ApplicationPolicy < ::ApplicationPolicy
    def index?
      user.present?
    end

    def show?
      user.present?
    end

    def create?
      false
    end

    def update?
      false
    end

    def destroy?
      false
    end

    class Scope < ::ApplicationPolicy::Scope
      def resolve
        scope.all
      end
    end
  end
end
