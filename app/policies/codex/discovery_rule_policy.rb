# frozen_string_literal: true

# Codex::DiscoveryRulePolicy — admin+ for everything.
#
# DiscoveryRules drive the unlock economy; allowing a `forester` to mint
# rules that unlock e.g. `mafusail` would devalue the Codex. Hence the
# strict `admin_or_above?` gate on every action including read.
module Codex
  class DiscoveryRulePolicy < Codex::ApplicationPolicy
    def index?
      admin_or_above?
    end

    def show?
      admin_or_above?
    end

    def create?
      admin_or_above?
    end

    def update?
      admin_or_above?
    end

    def destroy?
      admin_or_above?
    end

    class Scope < Codex::ApplicationPolicy::Scope
      def resolve
        return scope.none unless user
        return scope.none unless admin_or_above?

        scope.all
      end
    end
  end
end
