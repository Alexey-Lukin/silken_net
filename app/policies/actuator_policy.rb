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
      # [SEC.26] Те саме, що в `GatewayPolicy`: гілка `IS NULL` на `NOT NULL`-колонці
      # була недосяжною за побудовою.
      scope.joins(gateway: :cluster).where(clusters: { organization_id: organization_id })
    end
  end
end
