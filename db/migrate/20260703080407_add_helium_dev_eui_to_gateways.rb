# frozen_string_literal: true

# [ARCH.34 L3] dev_eui Helium-Console ↔ gateways: intake-мапінг SOS-webhook'а
# (HeliumSosWorker). Заповнюється при реєстрації Королеви у Console
# (👤-крок ARCH.34); NULL = Королева без Helium-fallback.
class AddHeliumDevEuiToGateways < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_column :gateways, :helium_dev_eui, :string
    add_index :gateways, :helium_dev_eui, unique: true, algorithm: :concurrently
  end
end
