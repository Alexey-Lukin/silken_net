# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class ActuatorPolicy < ApplicationPolicy
  def index?
    forester_or_above?
  end

  def show?
    forester_or_above?
  end

  def execute?
    forester_or_above?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.left_joins(gateway: :cluster)
           .where("clusters.organization_id = ? OR gateways.cluster_id IS NULL", organization_id)
    end
  end
end
