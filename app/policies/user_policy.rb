# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class UserPolicy < ApplicationPolicy
  def index?
    admin_or_above?
  end

  def show?
    # super_admin? дзеркалить Scope (super_admin → scope.all): без нього
    # super_admin бачить увесь список, але individual authorize кидав би 403
    # (org_id = nil ⇒ same_organization? завжди false). admin лишається
    # обмеженим своєю org — це навмисно (Scope: admin → where(org)).
    super_admin? || same_organization?(record.organization_id)
  end

  def me?
    true
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
