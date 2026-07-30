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
      # [SEC.26] Доти тут стояв `OR trees.cluster_id IS NULL` — тобто «безкластерне
      # дерево видиме КОЖНІЙ організації». Знято присудом 2026-07-30: осиротілий вузол
      # не має екстенсіоналу (заведення вимагає кластер криптографічно — без нього не
      # деривується K_ota), а `Cluster has_many :trees` тепер `restrict_with_error`,
      # тож координата не зануляється й на destroy. Скоуп вирівняно з трьома домами,
      # що вже так казали: `Organization#trees` (through `:clusters`),
      # `MaintenanceRecordPolicy::Scope` і живий `WalletPolicy::Scope`.
      scope.joins(:cluster).where(clusters: { organization_id: organization_id })
    end
  end
end
