# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# ⚖️ [FW.66 S4, ратифіковано 2026-10-10 — врізка `03_04 §7.3`] Ера дроту контракту (`ecb` · `ccm`),
# яку диспетчер OTA звіряє з пульсом Королеви. Дефолт `ecb` живе рівно один крок: кожен наявний
# контракт справді ECB (`calculate_state`), а далі ера — властивість байткоду, і нове завантаження
# мусить назвати її само (дефолт знято тим самим кроком).
class AddWireEraToBioContractFirmwares < ActiveRecord::Migration[8.1]
  def change
    add_column :bio_contract_firmwares, :wire_era, :string, null: false, default: "ecb"
    change_column_default :bio_contract_firmwares, :wire_era, from: "ecb", to: nil
  end
end
