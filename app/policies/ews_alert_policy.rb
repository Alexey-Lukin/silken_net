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
      if super_admin?
        scope.all
      else
        # Включаємо алерти кластерів організації ТА безкластерні алерти
        scope.left_joins(:cluster)
             .where("clusters.organization_id = ? OR ews_alerts.cluster_id IS NULL", user.organization_id)
      end
    end
  end
end
