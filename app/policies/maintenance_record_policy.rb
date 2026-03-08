# frozen_string_literal: true

class MaintenanceRecordPolicy < ApplicationPolicy
  def index?
    forester_or_above?
  end

  def show?
    forester_or_above?
  end

  def create?
    forester_or_above?
  end

  def update?
    forester_or_above?
  end

  def verify?
    forester_or_above?
  end

  def photos?
    forester_or_above?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      org_cluster_ids = Cluster.where(organization_id: user.organization_id).select(:id)
      tree_ids = Tree.where(cluster_id: org_cluster_ids).select(:id)
      gateway_ids = Gateway.where(cluster_id: org_cluster_ids).select(:id)

      scope.where(
        "(maintainable_type = 'Tree' AND maintainable_id IN (:tree_ids)) OR " \
        "(maintainable_type = 'Gateway' AND maintainable_id IN (:gateway_ids))",
        tree_ids: tree_ids, gateway_ids: gateway_ids
      )
    end
  end
end
