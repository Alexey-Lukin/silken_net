# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class GatewayPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    true
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.left_joins(:cluster)
           .where("clusters.organization_id = ? OR gateways.cluster_id IS NULL", organization_id)
    end
  end
end
