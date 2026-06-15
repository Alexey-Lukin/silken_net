# frozen_string_literal: true

# [SEC.3] Factory Flashing Pipeline — provisioning session tracking.
#
# Each row represents one Factory-Flashing attempt for a single device. The
# AASM state machine (see ProvisioningSession) enforces the 2-Person Rule
# documented in docs/03_06_Factory_Flashing_and_Key_Provisioning.md §5 C:
#
#   pending → supervisor_approved → active → completed | failed
#
# `gilka` distinguishes Гілка A (Protected Flash) from Гілка B (ATECC608B).
# `atecc_serial_hex` is NULL for Гілка A and populated (9-byte hex) for B.
# Index on (state, batch_id) supports batch progress dashboards.
class CreateProvisioningSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :provisioning_sessions do |t|
      t.string  :state,             null: false, default: "pending"
      t.string  :gilka,             null: false           # "A" or "B"
      t.string  :device_uid,        null: false           # raw STM32 UID96 hex
      t.string  :batch_id,          null: false           # operator-supplied tag
      t.string  :atecc_serial_hex                          # Гілка B only
      t.string  :firmware_version,  null: false
      t.string  :flash_addr,        null: false, default: "0x0803E000"
      t.integer :rdp_level,         null: false, default: 1

      t.references :operator,   foreign_key: { to_table: :users }, null: false
      t.references :supervisor, foreign_key: { to_table: :users }

      t.datetime :supervisor_approved_at
      t.datetime :started_at
      t.datetime :completed_at
      t.text     :error_message

      t.timestamps
    end

    add_index :provisioning_sessions, :device_uid
    add_index :provisioning_sessions, [ :state, :batch_id ]
  end
end
