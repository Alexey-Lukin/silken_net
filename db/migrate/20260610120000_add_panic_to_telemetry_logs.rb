# frozen_string_literal: true

# [FW.29] PanicFlag (біт 7 StatusByte) досі декодувався в анпакері лише для
# SEC.10 anti-replay і викидався — панічний рядок у telemetry_logs був
# невідрізнюваний від звичайного (маркер acoustic=255 колізує з FW.22-сатурацією).
#
# telemetry_logs.panic — per-record панічність з дроту. Робить панічність
# queryable і дає `relayed_via_mesh?` правильний стартовий TTL
# (PANIC_TTL=5 vs DEFAULT_TTL=3 — дзеркало firmware/soldier/main.c).
# Таблиця партиційована (RANGE по created_at) — ADD COLUMN з DEFAULT на
# PG16 metadata-only (без rewrite), каскадується на всі партиції.
class AddPanicToTelemetryLogs < ActiveRecord::Migration[8.1]
  def change
    add_column :telemetry_logs, :panic, :boolean, default: false, null: false
  end
end
