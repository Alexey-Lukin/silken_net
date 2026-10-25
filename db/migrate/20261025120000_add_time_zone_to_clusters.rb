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
# Ключ, що не є рядком-IANA (JSON-`null`, рейлзове «Kyiv», порожнеча), переноситись не сміє —
# він або зірвав би NOT NULL, або дав би колонку, яку відкидає власна валідація моделі; такий
# кластер лишається на UTC, і міграція називає його поіменно.
class AddTimeZoneToClusters < ActiveRecord::Migration[8.1]
  class MigrationCluster < ActiveRecord::Base
    self.table_name = "clusters"
  end

  def up
    add_column :clusters, :time_zone, :string, null: false, default: "UTC"
    iana = TZInfo::Timezone.all_identifiers.to_set
    MigrationCluster.where("environmental_settings ? 'timezone'").find_each do |cluster|
      raw = cluster.environmental_settings["timezone"]
      zone = raw.is_a?(String) && iana.include?(raw.strip) ? raw.strip : "UTC"
      say "cluster #{cluster.id}: timezone #{raw.inspect} не є IANA — лишено UTC", true if zone == "UTC" && raw != "UTC"
      cluster.update_columns(time_zone: zone, environmental_settings: cluster.environmental_settings.except("timezone"))
    end
    change_column_default :clusters, :time_zone, from: "UTC", to: nil
  end

  def down
    MigrationCluster.update_all(
      "environmental_settings = COALESCE(environmental_settings, '{}'::jsonb) || jsonb_build_object('timezone', time_zone)"
    )
    remove_column :clusters, :time_zone
  end
end
