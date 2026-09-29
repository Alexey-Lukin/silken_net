# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [FW.8 · ⚖️ founder 2026-09-29] Облік смуги Лоренца, яку може тримати пристрій:
# доказ — статус пакета там, де смуги-кандидати дають різний вердикт
# (Downlink::ThresholdBand, канон 03_04 §5.3).
#   held     — смуги (x100-пари [min, max]), які пристрій може тримати, крім
#              заводського дефолту: доведена + видані поверх неї, чий кадр міг
#              долетіти раніше за наступний. [] = лише дефолт
#   pending  — тіло 0x9A відкритої видачі (8 Б, байт-у-байт): перевидача
#              запечатує рівно його; dlfc + key_epoch — її нонс, і перевидача тим
#              самим кадром законна, лише поки ключ і лічильник не рушили
#   issued_at — початок вікна доставки; served_at — остання видача (NULL = пора)
#   stale_count — пакети зі СТАРОЮ смугою після вікна доставки
# ⚠️ held — jsonb, а не bytea[]: Rails 8.1 пише bytea[] сміттям (виміряно).
class AddLorenzBandLedgerToTrees < ActiveRecord::Migration[8.1]
  def change
    add_column :trees, :lorenz_band_held, :jsonb, default: [], null: false
    add_column :trees, :lorenz_band_pending, :binary
    add_column :trees, :lorenz_band_dlfc, :bigint
    add_column :trees, :lorenz_band_key_epoch, :integer
    add_column :trees, :lorenz_band_issued_at, :datetime
    add_column :trees, :lorenz_band_served_at, :datetime
    add_column :trees, :lorenz_band_stale_count, :integer, limit: 2, default: 0, null: false
  end
end
