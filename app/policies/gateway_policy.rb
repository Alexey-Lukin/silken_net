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
      # [SEC.26] `OR gateways.cluster_id IS NULL` знято — і тут воно було ще й
      # ДОКАЗОВО мертвим SQL: `gateways.cluster_id` має `NOT NULL` у схемі, тож гілка
      # не могла відпрацювати жодного разу. Копі-пейст із `TreePolicy`, а не позиція.
      scope.joins(:cluster).where(clusters: { organization_id: organization_id })
    end
  end
end
