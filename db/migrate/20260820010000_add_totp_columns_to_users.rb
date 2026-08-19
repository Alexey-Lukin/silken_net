# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [S6.21] TOTP-секрет другого фактора + анти-replay мітка.
#
# `otp_secret` — AR-encrypted на моделі (прецедент `hardware_keys.aes_key_hex`:
# at-rest ключі шифруються з ENV `ACTIVE_RECORD_ENCRYPTION_*`, boot-guard
# fail-closed без них — SEC.22). `otp_last_used_at` — час останнього УСПІШНОГО
# TOTP-входу: ROTP `verify(after:)` відкидає повтор того самого коду всередині
# 30-секундного вікна (перехоплений код не дає другого входу).
class AddTotpColumnsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :otp_secret, :string
    add_column :users, :otp_last_used_at, :datetime
  end
end
