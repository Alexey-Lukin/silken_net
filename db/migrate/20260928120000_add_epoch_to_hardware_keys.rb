# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [FW.17] Епоха ключа дерева (⚖️ founder 2026-09-28, 03_05 §3.8): кожен
# re-provision піднімає її, і корінь K0_e = HKDF(master, DID, info з епохою)
# не виводиться з жодного старого K_v — це і форма re-provision, і шлях
# відновлення після компрометації. e = 0 бітово дорівнює ключу до присуду,
# тож наявні рядки нічого не переписують. Королева епохи не вживає (її
# ротація — випадковий ключ, доставка — re-flash), колонка в неї лишається 0.
class AddEpochToHardwareKeys < ActiveRecord::Migration[8.1]
  def change
    add_column :hardware_keys, :epoch, :integer, default: 0, null: false
  end
end
