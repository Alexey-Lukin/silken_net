# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# ⚖️ [FW.66, делеговано 2026-10-09 — врізка `03_04 §7.3`] Крок 2 зняття колонок пари
# `critical_z_*`, смуги FW.8 на дереві й оргового порогу Z: моделі не бачать їх із
# кроку 1 (`ignored_columns`). `safety_assured` тут не обхід, а названа підстава:
# двокроковий танець існує проти rolling-деплою з ЖИВИМИ даними, а canopy — у Фазі ∅
# (`TERMINATED`, старого контейнера немає) і без даних й користувачів; дропнути й
# перестворити її базу дозволено founder-ом 2026-10-10.
class RemoveFw8ThresholdColumns < ActiveRecord::Migration[8.1]
  def change
    safety_assured do
      remove_column :tree_families, :critical_z_min, :numeric
      remove_column :tree_families, :critical_z_max, :numeric
      remove_column :organizations, :alert_threshold_critical_z, :numeric, precision: 5, scale: 2, default: 2.5
      remove_column :trees, :lorenz_band_held, :jsonb, default: [], null: false
      remove_column :trees, :lorenz_band_pending, :binary
      remove_column :trees, :lorenz_band_dlfc, :bigint
      remove_column :trees, :lorenz_band_key_epoch, :integer
      remove_column :trees, :lorenz_band_issued_at, :datetime
      remove_column :trees, :lorenz_band_served_at, :datetime
      remove_column :trees, :lorenz_band_stale_count, :integer, limit: 2, default: 0, null: false
    end
  end
end
