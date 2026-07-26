# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Codex
  class RealmPolicy < ApplicationPolicy
    def index?
      user.present?
    end

    def show?
      user.present?
    end

    class Scope < ApplicationPolicy::Scope
      def resolve
        scope.active
      end
    end
  end
end
