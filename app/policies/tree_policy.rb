# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class TreePolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    true
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      # Включаємо дерева в кластерах організації ТА безкластерні дерева
      scope.left_joins(:cluster)
           .where("clusters.organization_id = ? OR trees.cluster_id IS NULL", organization_id)
    end
  end
end
