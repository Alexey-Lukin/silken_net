# frozen_string_literal: true

class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    @user = user
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
    user.organization_id.present? && user.organization_id == resource_org_id
  end

  class Scope
    attr_reader :user, :scope

    def initialize(user, scope)
      @user = user
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
