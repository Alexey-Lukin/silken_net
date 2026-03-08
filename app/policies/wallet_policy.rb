# frozen_string_literal: true

class WalletPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    admin_or_above? ||
      same_organization?(record.organization_id) ||
      same_organization?(record.tree&.cluster&.organization_id)
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      if admin_or_above?
        scope.all
      else
        scope.where(organization_id: user.organization_id)
      end
    end
  end
end
