# frozen_string_literal: true

class GatewayPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    true
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      if super_admin?
        scope.all
      else
        scope.joins(:cluster).where(clusters: { organization_id: user.organization_id })
      end
    end
  end
end
