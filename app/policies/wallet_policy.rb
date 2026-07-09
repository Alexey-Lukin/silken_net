# frozen_string_literal: true

class WalletPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    # super_admin? (platform :system access), NOT admin_or_above? — a plain admin is
    # org-scoped (:organization access, user.rb#access_level / 04_01). Using
    # admin_or_above? here leaked every org's treasury to any org-admin (SEC.16).
    super_admin? ||
      same_organization?(record.organization_id) ||
      same_organization?(record.tree&.cluster&.organization_id)
  end

  def balance?
    show?
  end

  def metadata?
    show?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      if super_admin? # platform-wide only; a plain admin is org-scoped (SEC.16)
        scope.all
      else
        scope.where(organization_id: user.organization_id)
      end
    end
  end
end
