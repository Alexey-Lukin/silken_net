# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class NaasContractPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    # super_admin? not admin_or_above? — a plain admin is org-scoped; using
    # admin_or_above? leaked every org's NaaS financials cross-tenant (SEC.16).
    super_admin? || same_organization?(record.organization_id)
  end

  def stats?
    true
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
