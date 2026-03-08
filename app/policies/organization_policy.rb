# frozen_string_literal: true

class OrganizationPolicy < ApplicationPolicy
  def index?
    super_admin?
  end

  def show?
    super_admin?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      if super_admin?
        scope.all
      else
        scope.where(id: user.organization_id)
      end
    end
  end
end
