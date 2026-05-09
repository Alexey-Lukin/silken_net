# frozen_string_literal: true

# Codex::MatchPolicy — read own + leaderboard public, write any-auth.
#
# Throttling lives at Rack::Attack (`60 votes / 1 minute / actor`); this
# policy answers "may this user act?" only.
module Codex
  class MatchPolicy < Codex::ApplicationPolicy
    def index?
      user.present?
    end

    def show?
      user.present? && record.user_id == user.id
    end

    def create?
      user.present?
    end

    class Scope < Codex::ApplicationPolicy::Scope
      def resolve
        return scope.none unless user

        scope.where(user_id: user.id)
      end
    end
  end
end
