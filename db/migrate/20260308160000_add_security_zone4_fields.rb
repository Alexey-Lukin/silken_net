# frozen_string_literal: true

# Зона 4: Security & Access
# 10. User: MFA/TOTP полія (otp_required_for_login, recovery_codes)
# 11. Identity: locked_at + primary прапорець
# 12. Organization: data_region для GDPR/Sharding
class AddSecurityZone4Fields < ActiveRecord::Migration[8.1]
  def change
    # --- User: MFA & Emergency Access ---
    add_column :users, :otp_required_for_login, :boolean, default: false, null: false
    add_column :users, :recovery_codes, :text

    # --- Identity: Account Takeover Protection ---
    add_column :identities, :locked_at, :datetime
    add_column :identities, :primary, :boolean, default: false, null: false

    # --- Organization: Data Residency ---
    add_column :organizations, :data_region, :string, default: "eu-west"
  end
end
