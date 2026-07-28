# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class ClusterPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    true
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.where(organization_id: organization_id)
    end
  end
end
