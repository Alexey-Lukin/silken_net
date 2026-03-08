# frozen_string_literal: true

class AuditLogPolicy < ApplicationPolicy
  def index?
    admin_or_above?
  end

  def show?
    admin_or_above?
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
