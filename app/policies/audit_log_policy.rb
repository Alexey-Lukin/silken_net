# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class AuditLogPolicy < ApplicationPolicy
  def index?
    admin_or_above?
  end

  # [SEC.25 Ф2] Роль лишається умовою (журнал не для лісника й не для інвестора),
  # але вже НЕ дає крос-тенантного доступу: `super_admin?` відмикав будь-чий журнал,
  # тепер усі читають рівно acting-організацію. `index?` лишається суто рольовим —
  # org-фільтр там робить `Scope`.
  def show?
    admin_or_above? && same_organization?(record.organization_id)
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.where(organization_id: organization_id)
    end
  end
end
