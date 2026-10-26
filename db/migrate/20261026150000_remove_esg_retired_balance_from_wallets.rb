# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# ⚖️ [ARCH.95] (В), крок 2б — founder 2026-10-26: тракт погашення знято, модель колонку не бачить
# із кроку 2а (`ignored_columns`). Відвантажено без живого зонда, бо бази з даними, яку двокроковий
# танець стереже, немає ніде: production не деплоївся, а canopy на підйомі перезасівають (шапка анкера,
# «ЦІНА»). `safety_assured` — ця названа підстава, не обхід.
#
# 🔴 CHECK `wallets_balance_invariants` називає колонку, а `DROP COLUMN` зносить багатоколонковий CHECK
# ЦІЛКОМ — разом із `balance >= 0` і `locked_balance <= balance`. Тому обмеження знімається й ставиться
# назад у ТІЙ САМІЙ транзакції, без доданка колонки; `NOT VALID` стереже нові записи одразу, а наявні
# рядки перевіряє наступна міграція (strong_migrations відкидає валідацію в транзакції, що тримає записи).
# Носій — приклади «DB CHECK wallets_balance_invariants» у `spec/models/wallet_spec.rb`.
#
# Відкат: `kamal rollback` на образ, старіший за 2а, падає на INSERT у `wallets` — той образ колонку ще
# пише. `down` повертає колонку І старий CHECK: форма `change` повернула б колонку без жодного money-CHECK.
class RemoveEsgRetiredBalanceFromWallets < ActiveRecord::Migration[8.1]
  CHECK_NAME = "wallets_balance_invariants"
  CHECK_WITHOUT_ESG = "balance >= 0 AND locked_balance >= 0 AND locked_balance <= balance"
  CHECK_WITH_ESG = "balance >= 0 AND locked_balance >= 0 AND esg_retired_balance >= 0 AND locked_balance <= balance"

  def up
    # Гард лічить ПІСЛЯ зняття обмеження: `ALTER TABLE` уже тримає ACCESS EXCLUSIVE, тож між
    # підрахунком і `DROP COLUMN` ніхто не допише значення, яке пропало б без сліду.
    remove_check_constraint :wallets, name: CHECK_NAME
    retired = select_value("SELECT count(*) FROM wallets WHERE esg_retired_balance <> 0").to_i
    if retired.positive?
      raise "[ARCH.95] #{retired} гаманців несуть ненульовий esg_retired_balance — колонку не знято. " \
            "Живого писача в неї немає з 2026-10-26, тож це дані старого сіду чи ручного запису: " \
            "розберись, чиї вони, перш ніж їх стерти."
    end

    safety_assured { remove_column :wallets, :esg_retired_balance }
    add_check_constraint :wallets, CHECK_WITHOUT_ESG, name: CHECK_NAME, validate: false
  end

  def down
    remove_check_constraint :wallets, name: CHECK_NAME
    add_column :wallets, :esg_retired_balance, :decimal, precision: 24, scale: 6, default: 0.0, null: false
    add_check_constraint :wallets, CHECK_WITH_ESG, name: CHECK_NAME
  end
end
