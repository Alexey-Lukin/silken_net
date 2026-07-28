# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class UserPolicy < ApplicationPolicy
  def index?
    admin_or_above?
  end

  # [SEC.25 Ф2] Дзеркалить `Scope` — і саме тому знімається ПАРОЮ з ним. Доти обидва
  # робили виняток для платформеної ролі; тепер обидва питають одне: чи запис
  # належить організації, в контексті якої виконується запит.
  def show?
    same_organization?(record.organization_id)
  end

  def me?
    true
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.where(organization_id: organization_id)
    end
  end
end
