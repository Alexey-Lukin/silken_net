# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [FW.17] Downlink Frame Counter — анти-повтор адресних команд Rails → Солдат
# (downlink-wire-ревізія, ⚖️ founder 2026-09-28, 03_05 §2.5). Один u32 на
# пристрій: видається команді один раз, при ВИДАЧІ, і живе з нею; у нонсі
# CCM — цілком, в ефірі — молодші 16 біт. bigint, бо стеля — 0xFFFFFFFF, а
# integer Postgres знаковий. 0 = жодної команди; re-provision обнуляє разом з
# новою епохою ключа, бо свіжий журнал Flash-KV запису DLFC не несе.
class AddDownlinkFrameCounterToHardwareKeys < ActiveRecord::Migration[8.1]
  def change
    add_column :hardware_keys, :downlink_frame_counter, :bigint, default: 0, null: false
  end
end
