# frozen_string_literal: true

class ActuatorPolicy < ApplicationPolicy
  def index?
    forester_or_above?
  end

  def show?
    forester_or_above?
  end

  def execute?
    forester_or_above?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      if super_admin?
        scope.all
      else
        scope.joins(gateway: :cluster).where(clusters: { organization_id: user.organization_id })
      end
    end
  end
end
