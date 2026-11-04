# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# ⚖️ [SEC.18, форма B — crypto-shredding, founder 2026-11-04] Ключ СУБʼЄКТА, яким
# `AuditLog` шифрує `ip_address`/`user_agent` ДО обчислення `chain_hash`. Знищення ключа
# (`Gdpr::AnonymizeUserService`) і є стиранням: жоден рядок журналу не переписується,
# ланцюг верифікується далі, бо хешує ШИФРОТЕКСТ.
#
# Nullable, без дефолту й без backfill свідомо: ключ народжується ЛИНИВО, при першому
# записі ip/ua субʼєкта (`User#audit_pii_key!`), тож користувач без такого сліду ключа
# не має взагалі. At-rest — AR-encryption (`encrypts :audit_pii_key`, прецедент `otp_secret`).
class AddAuditPiiKeyToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :audit_pii_key, :string
  end
end
