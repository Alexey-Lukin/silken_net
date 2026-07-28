# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class ApplicationPolicy
  # [SEC.25 Ф2] Розпаковує `UserContext` → (справжній `User`, id acting-організації).
  # Приймає й голий `User` — так політику конструюють спеки, і так вона поводилась
  # до acting-org. Для всіх, крім super_admin, обидва входи дають те саме, бо
  # acting-організація тотожна власній.
  module ContextUnpacking
    attr_reader :user, :organization_id

    def unpack_actor(actor)
      if actor.is_a?(UserContext)
        @user = actor.user
        @organization_id = actor.organization_id
      else
        @user = actor
        @organization_id = actor&.organization_id
      end
    end
  end

  include ContextUnpacking

  attr_reader :record

  def initialize(user, record)
    unpack_actor(user)
    @record = record
  end

  def index?
    true
  end

  def show?
    true
  end

  def create?
    admin_or_above?
  end

  def update?
    admin_or_above?
  end

  def destroy?
    admin_or_above?
  end

  private

  def admin_or_above?
    user.role_admin? || user.role_super_admin?
  end

  def super_admin?
    user.role_super_admin?
  end

  def forester_or_above?
    user.forest_commander?
  end

  def same_organization?(resource_org_id)
    organization_id.present? && organization_id == resource_org_id
  end

  class Scope
    include ContextUnpacking

    attr_reader :scope

    def initialize(user, scope)
      unpack_actor(user)
      @scope = scope
    end

    def resolve
      scope.all
    end

    private

    def admin_or_above?
      user.role_admin? || user.role_super_admin?
    end

    def super_admin?
      user.role_super_admin?
    end
  end
end
