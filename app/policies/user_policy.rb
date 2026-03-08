# frozen_string_literal: true

class UserPolicy < ApplicationPolicy
  def index?
    admin_or_above?
  end

  def me?
    true
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      if super_admin?
        scope.all
      else
        scope.where(organization_id: user.organization_id)
      end
    end
  end
end
