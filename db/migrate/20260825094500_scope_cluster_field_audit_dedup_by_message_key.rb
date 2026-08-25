# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [ARCH.110] Cluster-level Field-Audit: дедуп за (кластер, ПРИЧИНА), не за кластером.
#
# ⚖️ Присуд founder 2026-08-25. Доти партковий unique-індекс тримав РІВНО ОДНУ
# активну cluster-level ескалацію на кластер — незалежно від того, що саме вона
# стверджує. А стверджували вони протилежне: «кластер осліп» (blackout) ⊥ «кошти
# заморожено до класифікації» (slash-freeze) ⊥ «страховий кандидат озброєний».
# Продюсер, що приходив другим, діставав `nil` та INFO-лог, і виклик-сайти на `nil`
# не реагують за побудовою — тобто після slash-freeze справжній blackout не був би
# записаний НІДЕ, хоч це вироки з різними діями людини.
#
# Анти-спам, заради якого індекс і ставили, при цьому НЕ слабшає: щоденний cron
# при тривалій деградації шле той самий `message_key`, тож дедуплікується далі.
# Розрізняються лише різні вердикти.
class ScopeClusterFieldAuditDedupByMessageKey < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  INDEX_NAME = "index_ews_alerts_unique_active_cluster_field_audit"
  # alert_type=7 (:field_audit), status=0 (:active) — числа, бо частковий індекс
  # живе в SQL і enum-імена йому недоступні.
  CONDITION = "((alert_type = 7) AND (status = 0) AND (tree_id IS NULL))"

  def up
    remove_index :ews_alerts, name: INDEX_NAME, algorithm: :concurrently
    add_index :ews_alerts, %i[cluster_id message_key],
              unique: true, where: CONDITION, name: INDEX_NAME, algorithm: :concurrently
  end

  def down
    remove_index :ews_alerts, name: INDEX_NAME, algorithm: :concurrently
    add_index :ews_alerts, :cluster_id,
              unique: true, where: CONDITION, name: INDEX_NAME, algorithm: :concurrently
  end
end
