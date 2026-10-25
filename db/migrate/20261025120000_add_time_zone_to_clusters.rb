# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# ⚖️ [SEC.37, ратифіковано founder 2026-10-25] Момент візиту лісника читається й друкується
# в зоні ДІЛЯНКИ, тож зона стає колонкою кластера (IANA), а не ключем JSONB-мішка
# `environmental_settings`: той мішок переписують цілим хешем, і зона зникала б від будь-якого
# запису налаштувань вогню, а валідації й NOT NULL ключ мати не може.
#
# Значення, що вже лежало в мішку, ПЕРЕНОСИТЬСЯ, а не замінюється дефолтом: сідовий київський
# кластер, який став би «UTC», — це вигадана зона з виглядом заданої. «UTC» отримує лише
# кластер, у якого ключа не було, — і для нього це правда: досі кожен його запис читали в UTC.
class AddTimeZoneToClusters < ActiveRecord::Migration[8.1]
  class MigrationCluster < ActiveRecord::Base
    self.table_name = "clusters"
  end

  def up
    add_column :clusters, :time_zone, :string, null: false, default: "UTC"
    MigrationCluster.where("environmental_settings ? 'timezone'").update_all(
      "time_zone = environmental_settings->>'timezone', " \
      "environmental_settings = environmental_settings - 'timezone'"
    )
    change_column_default :clusters, :time_zone, from: "UTC", to: nil
  end

  def down
    MigrationCluster.update_all(
      "environmental_settings = COALESCE(environmental_settings, '{}'::jsonb) || jsonb_build_object('timezone', time_zone)"
    )
    remove_column :clusters, :time_zone
  end
end
