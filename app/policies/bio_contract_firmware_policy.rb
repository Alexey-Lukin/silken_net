# frozen_string_literal: true

class BioContractFirmwarePolicy < ApplicationPolicy
  def index?
    admin_or_above?
  end

  def show?
    admin_or_above?
  end

  def create?
    admin_or_above?
  end

  def inventory?
    admin_or_above?
  end

  def deploy?
    admin_or_above?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.all
    end
  end
end
