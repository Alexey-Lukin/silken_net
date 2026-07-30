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
      # [SEC.26] Дзеркало `TreePolicy::Scope` — `OR ews_alerts.cluster_id IS NULL` знято
      # тим самим присудом (розбір там же). Вирівняно з `Organization#ews_alerts`,
      # яка вже йде through `:clusters`.
      scope.joins(:cluster).where(clusters: { organization_id: organization_id })
    end
  end
end
