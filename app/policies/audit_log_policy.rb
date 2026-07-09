# frozen_string_literal: true

class AuditLogPolicy < ApplicationPolicy
  def index?
    admin_or_above?
  end

  def show?
    # super_admin? (platform :system) sees any org's log; a plain admin is org-scoped,
    # so gate the record on same-organization — mirrors WalletPolicy/NaasContractPolicy
    # (SEC.16). index? stays role-only: its Scope does the org filtering.
    super_admin? || (admin_or_above? && same_organization?(record.organization_id))
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
