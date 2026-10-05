# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [SEC.40, ⚖️ founder 2026-10-05] Ковзне вікно анти-повтору CCM-кадрів на пару (DID, епоха
# ключа), як у RFC 4303: найвищий прийнятий FC, точний дедуп усередині вікна (біт k = кадр
# top_fc − k) і підлога, на якій і нижче кадр відкидається завжди. Окрема таблиця, бо рядок
# `hardware_keys` ключем (DID, епоха) бути не може: кадри grace після re-provision приходять
# попередньою епохою. `floor_fc` піднімає DR-крок після відкату БД (06_06 §5.8) — ончейн-мінти
# не відкочуються, тож межа мусить іти вгору, а не назад разом із бекапом. Ширина бітової
# карти = `CcmReplayWindow::WINDOW`; міняти разом.
class CreateCcmReplayWindows < ActiveRecord::Migration[8.1]
  def change
    create_table :ccm_replay_windows do |t|
      t.string  :device_uid, null: false
      t.integer :key_epoch, null: false
      t.integer :top_fc, null: false
      t.integer :floor_fc, null: false, default: 0
      t.column  :seen, "bit(4096)", null: false
      t.timestamps
    end
    add_index :ccm_replay_windows, %i[device_uid key_epoch], unique: true
  end
end
