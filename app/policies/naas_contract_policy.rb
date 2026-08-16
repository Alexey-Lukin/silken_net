# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class NaasContractPolicy < ApplicationPolicy
  def index?
    true
  end

  # [SEC.25 Ф2] Фінанси NaaS бачить лише acting-організація. `admin_or_above?` тут
  # свого часу зливав їх крос-тенантно (SEC.16), `super_admin?` — робив те саме
  # роллю вище; лишилась одна умова, спільна для всіх.
  def show?
    same_organization?(record.organization_id)
  end

  def stats?
    true
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none if no_acting_organization?

      scope.where(organization_id: organization_id)
    end
  end
end
