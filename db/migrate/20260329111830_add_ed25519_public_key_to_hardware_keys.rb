class AddEd25519PublicKeyToHardwareKeys < ActiveRecord::Migration[8.1]
  def change
    add_column :hardware_keys, :ed25519_public_key_hex, :string
  end
end
