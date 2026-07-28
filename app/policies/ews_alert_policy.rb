# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class EwsAlertPolicy < ApplicationPolicy
  def index?
    true
  end

  def resolve?
    forester_or_above?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      # Включаємо алерти кластерів організації ТА безкластерні алерти
      scope.left_joins(:cluster)
           .where("clusters.organization_id = ? OR ews_alerts.cluster_id IS NULL", organization_id)
    end
  end
end
